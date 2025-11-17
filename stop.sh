#!/bin/bash
# Stop interactive pods and cleanup port-forwards
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

NAMESPACE=$(jq -r '.namespace' "$CONFIG_FILE")

echo "Stopping interactive pods and port-forwards..."

# Check for port-forwards
PORT_FORWARDS=$(ps aux | grep '[k]ubectl.*port-forward' | grep -v grep || true)
if [ -n "$PORT_FORWARDS" ]; then
    echo "🔌 Port-forward processes:"
    echo "$PORT_FORWARDS"
    echo ""
    echo "Kill all port-forwards? (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        pkill -f 'kubectl.*port-forward' || true
        echo "✅ Port-forwards killed"
    else
        echo "Port-forwards not killed"
    fi
fi

# Get interactive pods
PODS=$(kubectl get pods -n "$NAMESPACE" -l app=interactive-ssh --no-headers 2>/dev/null | awk '{print $1}' || true)

if [ -z "$PODS" ]; then
    echo "No interactive pods found in namespace: $NAMESPACE"
    exit 0
fi

echo ""
echo "Found interactive pods:"
POD_ARRAY=()
while IFS= read -r pod; do
    POD_ARRAY+=("$pod")
    STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "  - $pod ($STATUS)"
done <<< "$PODS"

echo ""
echo "Select pods to delete:"
echo "  1) Delete all pods"
echo "  2) Select specific pods"
echo "  3) Cancel"
read -r choice

case $choice in
    1)
        echo "Deleting all pods..."
        for pod in "${POD_ARRAY[@]}"; do
            echo "  Deleting $pod..."
            kubectl delete pod "$pod" -n "$NAMESPACE"
            # Cleanup port mapping
            PORT_MAPPINGS_FILE="$HOME/.kube/pod-port-mappings.json"
            if [ -f "$PORT_MAPPINGS_FILE" ]; then
                TMP=$(mktemp)
                jq "del(.\"$pod\")" "$PORT_MAPPINGS_FILE" > "$TMP"
                mv "$TMP" "$PORT_MAPPINGS_FILE"
            fi
        done
        echo "✅ All pods deleted"
        ;;
    2)
        echo "Select pods to delete (space-separated numbers, e.g., 1 3 5):"
        for i in "${!POD_ARRAY[@]}"; do
            echo "  $((i+1))) ${POD_ARRAY[$i]}"
        done
        read -r selections
        
        for num in $selections; do
            idx=$((num-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#POD_ARRAY[@]} ]; then
                pod="${POD_ARRAY[$idx]}"
                echo "  Deleting $pod..."
                kubectl delete pod "$pod" -n "$NAMESPACE"
                # Cleanup port mapping
                PORT_MAPPINGS_FILE="$HOME/.kube/pod-port-mappings.json"
                if [ -f "$PORT_MAPPINGS_FILE" ]; then
                    TMP=$(mktemp)
                    jq "del(.\"$pod\")" "$PORT_MAPPINGS_FILE" > "$TMP"
                    mv "$TMP" "$PORT_MAPPINGS_FILE"
                fi
            fi
        done
        echo "✅ Selected pods deleted"
        ;;
    3)
        echo "Cancelled"
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

