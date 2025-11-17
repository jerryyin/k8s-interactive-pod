#!/bin/bash
# Connect to or create an interactive Kubernetes development pod with SSH access
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    echo "   Please copy config.json.example to config.json and customize it"
    exit 1
fi

NAMESPACE=$(jq -r '.namespace' "$CONFIG_FILE")
PVC_CLAIM_NAME=$(jq -r '.pvc' "$CONFIG_FILE")
USERNAME=$(jq -r '.username' "$CONFIG_FILE")
SSH_PUBLIC_KEY_PATH=$(eval echo $(jq -r '.public_ssh_key_path' "$CONFIG_FILE"))
# Derive private key path from public key (remove .pub)
SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"
DOCKER_IMAGE=$(jq -r '.docker_image // "rocm/dev-ubuntu-24.04:latest"' "$CONFIG_FILE")

# SSH command options as array (proper argument splitting)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardAgent=yes -i "${SSH_PRIVATE_KEY_PATH}")

# Parse arguments
EPHEMERAL=false
SKIP_CREATE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--ephemeral)
            EPHEMERAL=true
            shift
            ;;
        --new)
            SKIP_CREATE=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

echo "🔧 Connecting to Kubernetes interactive pod..."

# Check authentication
echo "Checking authentication - Open http://localhost:8000 from browser ..."
if ! kubectl get ns &>/dev/null; then
    echo "❌ Not authenticated with Kubernetes cluster"
    exit 1
fi
echo "✓ Authenticated with Kubernetes cluster"

# Check for existing pods
echo "Checking for existing interactive pods..."
EXISTING_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=interactive-ssh --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

if [ -n "$EXISTING_PODS" ]; then
    echo "Found existing pod(s):"
    POD_ARRAY=()
    while IFS= read -r pod; do
        POD_ARRAY+=("$pod")
        echo "  - $pod"
    done <<< "$EXISTING_PODS"
    
    echo ""
    echo "Select a pod to connect to (or 'n' to create new):"
    select pod_choice in "${POD_ARRAY[@]}" "Create new pod"; do
        if [ "$pod_choice" = "Create new pod" ]; then
            SKIP_CREATE=false
            break
        elif [ -n "$pod_choice" ]; then
            POD_NAME="$pod_choice"
            SKIP_CREATE=true
            break
        fi
    done
fi

# Create new pod if needed
if [ "$SKIP_CREATE" = "false" ]; then
    # Generate pod name
    POD_NAME="${USERNAME}-dev-$(date +%m%d-%H%M%S)"
    SSH_SECRET_NAME="ssh-key-${USERNAME}"
    
    echo "Creating new pod: $POD_NAME"
    
    # Update or create SSH key secret
    echo "Setting up SSH key secret..."
    if [ ! -f "$SSH_PUBLIC_KEY_PATH" ]; then
        echo "❌ SSH public key not found: $SSH_PUBLIC_KEY_PATH"
        exit 1
    fi
    
    if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
        echo "❌ SSH private key not found: $SSH_PRIVATE_KEY_PATH"
        echo "   (Needed for SSH authentication)"
        exit 1
    fi
    
    kubectl delete secret "$SSH_SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true
    kubectl create secret generic "$SSH_SECRET_NAME" \
        --from-file=authorized_keys="$SSH_PUBLIC_KEY_PATH" \
        -n "$NAMESPACE"
    echo "✅ SSH key secret created/updated"
    
    # Prepare pod YAML
    if [ "$EPHEMERAL" = "true" ]; then
        TEMPLATE="$SCRIPT_DIR/pod-ssh-ephemeral.yml"
        echo "Using ephemeral mode (no persistent storage)"
    else
        TEMPLATE="$SCRIPT_DIR/pod-ssh.yml"
        echo "Using persistent mode (PVC: $PVC_CLAIM_NAME)"
    fi
    
    POD_YAML=$(mktemp)
    sed -e "s/{{POD_NAME}}/$POD_NAME/g" \
        -e "s/{{PVC_CLAIM_NAME}}/$PVC_CLAIM_NAME/g" \
        -e "s/{{SSH_SECRET_NAME}}/$SSH_SECRET_NAME/g" \
        -e "s/{{USERNAME}}/$USERNAME/g" \
        -e "s|{{DOCKER_IMAGE}}|$DOCKER_IMAGE|g" \
        "$TEMPLATE" > "$POD_YAML"
    
    # Apply pod
    echo "Creating pod..."
    kubectl apply -f "$POD_YAML" -n "$NAMESPACE"
    rm "$POD_YAML"
    
    # Wait for pod to be ready
    echo "Waiting for pod to be ready (this may take 5-15 minutes for first-time image pull)..."
    if ! kubectl wait --for=condition=ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=900s; then
        echo "❌ Pod failed to become ready. Check status with:"
        echo "   kubectl describe pod $POD_NAME -n $NAMESPACE"
        echo "   kubectl logs $POD_NAME -n $NAMESPACE"
        exit 1
    fi
    echo "✅ Pod is ready"
fi

# Setup port forwarding
PORT_MAPPINGS_FILE="$HOME/.kube/pod-port-mappings.json"
mkdir -p "$(dirname "$PORT_MAPPINGS_FILE")"
touch "$PORT_MAPPINGS_FILE"

allocate_new_port() {
    local start_port=${1:-2222}
    SSH_PORT=$start_port
    while jq -e "to_entries[] | select(.value == $SSH_PORT)" "$PORT_MAPPINGS_FILE" &>/dev/null; do
        ((SSH_PORT++))
    done
    TMP=$(mktemp)
    jq ". + {\"$POD_NAME\": $SSH_PORT}" "$PORT_MAPPINGS_FILE" > "$TMP"
    mv "$TMP" "$PORT_MAPPINGS_FILE"
}

remove_port_mapping() {
    TMP=$(mktemp)
    jq "del(.\"$POD_NAME\")" "$PORT_MAPPINGS_FILE" > "$TMP"
    mv "$TMP" "$PORT_MAPPINGS_FILE"
}

start_port_forward() {
PORT_FORWARD_LOG="/tmp/port-forward-${POD_NAME}.log"
PORT_FORWARD_RESTARTS=0
PORT_FORWARD_PID=""

summarize_port_forward_error() {
    local reason output
    if [ -s "$PORT_FORWARD_LOG" ]; then
        reason=$(grep -o 'err="[^"]*"' "$PORT_FORWARD_LOG" | tail -n 1 || true)
        reason=${reason#err=\"}
        reason=${reason%\"}
        if [ -z "$reason" ]; then
            reason=$(tail -n 1 "$PORT_FORWARD_LOG")
        fi
        output=$(echo "$reason" | head -c 160)
        echo "⚠️  Port-forward restart #$PORT_FORWARD_RESTARTS (${output:-connection error})"
    else
        echo "⚠️  Port-forward restart #$PORT_FORWARD_RESTARTS"
    fi
}

start_port_forward() {
    PORT_FORWARD_ATTEMPTS=0
    MAX_PORT_FORWARD_ATTEMPTS=5

    while true; do
        ((++PORT_FORWARD_ATTEMPTS))
        if (( PORT_FORWARD_RESTARTS > 0 )); then
            if (( PORT_FORWARD_ATTEMPTS == 1 )); then
                echo "↻ Restarting port-forward on localhost:$SSH_PORT -> pod:22"
            else
                echo "   ↳ retry $PORT_FORWARD_ATTEMPTS"
            fi
        else
            if (( PORT_FORWARD_ATTEMPTS == 1 )); then
                echo "Starting port-forward: localhost:$SSH_PORT -> pod:22"
            else
                echo "   ↳ retry $PORT_FORWARD_ATTEMPTS"
            fi
        fi
        : > "$PORT_FORWARD_LOG"
        kubectl port-forward "$POD_NAME" "$SSH_PORT:22" -n "$NAMESPACE" >"$PORT_FORWARD_LOG" 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 2

        if ps -p "$PORT_FORWARD_PID" >/dev/null 2>&1; then
            echo "✅ Port-forward started (PID: $PORT_FORWARD_PID)"
            break
        fi

        echo "⚠️  Port-forward failed to start (port $SSH_PORT may be busy)."
        summarize_port_forward_error

        if [ "$PORT_FORWARD_ATTEMPTS" -ge "$MAX_PORT_FORWARD_ATTEMPTS" ]; then
            echo "❌ Unable to start port-forward after $MAX_PORT_FORWARD_ATTEMPTS attempts."
            echo "   Check $PORT_FORWARD_LOG for full details."
            exit 1
        fi

        # Remove stale mapping and try the next available port
        local next_port=$((SSH_PORT + 1))
        remove_port_mapping
        allocate_new_port "$next_port"
        sleep 1
    done
}
}

# Get or allocate port
SSH_PORT=$(jq -r ".\"$POD_NAME\" // empty" "$PORT_MAPPINGS_FILE" 2>/dev/null || echo "")
if [ -z "$SSH_PORT" ]; then
    allocate_new_port
fi

# Kill existing port-forward for this pod
pkill -f "kubectl.*port-forward.*$POD_NAME.*:22" || true
sleep 1

start_port_forward

# Wait for SSH to be ready
echo "Waiting for SSH service to be ready..."
echo "(Waiting for port-forward to establish and SSH daemon to start; press Ctrl+C to abort)"
SSH_WAIT_ATTEMPTS=0
while true; do
    ((++SSH_WAIT_ATTEMPTS))
    if ! ps -p "$PORT_FORWARD_PID" >/dev/null 2>&1; then
        ((++PORT_FORWARD_RESTARTS))
        summarize_port_forward_error
        start_port_forward
    fi
    if ssh -o ConnectTimeout=2 "${SSH_OPTS[@]}" -p "$SSH_PORT" "${USERNAME}@localhost" "exit 0" >/dev/null 2>&1; then
        echo "✅ SSH service is ready!"
        break
    fi
    if (( SSH_WAIT_ATTEMPTS % 30 == 0 )); then
        echo "  ...still waiting for SSH (attempt ${SSH_WAIT_ATTEMPTS}). Pod may still be configuring."
    fi
    sleep 2
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Pod Ready!"
echo "════════════════════════════════════════════════════════════════"
echo "  Pod:   $POD_NAME"
echo "  SSH:   ssh -i ${SSH_PRIVATE_KEY_PATH} -p $SSH_PORT ${USERNAME}@localhost"
echo "  Port:  $SSH_PORT"
echo ""
echo "  💡 Tip: Add to ~/.ssh/config for easier access:"
echo "     Host ${USERNAME}-pod"
echo "       HostName localhost"
echo "       Port $SSH_PORT"
echo "       User $USERNAME"
echo "       IdentityFile ${SSH_PRIVATE_KEY_PATH}"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Connect to pod
echo "Connecting to pod..."
ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "${USERNAME}@localhost"

