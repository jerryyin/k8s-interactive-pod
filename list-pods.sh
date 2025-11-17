#!/bin/bash
# List active interactive pods with connection information
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

NAMESPACE=$(jq -r '.namespace' "$CONFIG_FILE")
USERNAME=$(jq -r '.username' "$CONFIG_FILE")
SSH_PUBLIC_KEY_PATH=$(eval echo $(jq -r '.public_ssh_key_path' "$CONFIG_FILE"))
# Derive private key path from public key (remove .pub)
SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"
PORT_MAPPINGS_FILE="$HOME/.kube/pod-port-mappings.json"

echo "═══════════════════════════════════════════════════════════════"
echo "  Interactive Pods in namespace: $NAMESPACE"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get pods
PODS=$(kubectl get pods -n "$NAMESPACE" -l app=interactive-ssh --no-headers 2>/dev/null | awk '{print $1}' || true)

if [ -z "$PODS" ]; then
    echo "No interactive pods found"
    exit 0
fi

while IFS= read -r pod; do
    # Get pod status
    STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    AGE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "Unknown")
    NODE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Unknown")
    
    # Get container state details
    CONTAINER_STATE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "{}")
    if echo "$CONTAINER_STATE" | jq -e '.running' >/dev/null 2>&1; then
        CONTAINER_STATUS="Running"
        STARTED_AT=$(echo "$CONTAINER_STATE" | jq -r '.running.startedAt')
    elif echo "$CONTAINER_STATE" | jq -e '.waiting' >/dev/null 2>&1; then
        CONTAINER_STATUS="Waiting"
        WAIT_REASON=$(echo "$CONTAINER_STATE" | jq -r '.waiting.reason')
        CONTAINER_STATUS="$CONTAINER_STATUS ($WAIT_REASON)"
    elif echo "$CONTAINER_STATE" | jq -e '.terminated' >/dev/null 2>&1; then
        CONTAINER_STATUS="Terminated"
    else
        CONTAINER_STATUS="Unknown"
    fi
    
    # Get conditions
    READY_CONDITION=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    CONTAINERS_READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ContainersReady")].status}' 2>/dev/null || echo "Unknown")
    
    # Get port mapping
    PORT=$(jq -r ".\"$pod\" // \"not-mapped\"" "$PORT_MAPPINGS_FILE" 2>/dev/null || echo "not-mapped")
    
    # Check if port-forward is running
    PF_PID=$(ps aux | grep "[k]ubectl.*port-forward.*$pod.*:22" | awk '{print $2}' || true)
    if [ -n "$PF_PID" ]; then
        PF_STATUS="running (PID: $PF_PID)"
    else
        PF_STATUS="not running"
    fi
    
    # Display pod information
    echo "📦 $pod"
    echo "   Status:        $STATUS"
    echo "   Container:     $CONTAINER_STATUS"
    if [ "$CONTAINER_STATUS" = "Running" ] && [ -n "$STARTED_AT" ]; then
        echo "   Started:       $STARTED_AT"
    fi
    echo "   Conditions:    Ready=$READY_CONDITION, ContainersReady=$CONTAINERS_READY"
    echo "   Node:          $NODE"
    echo "   Age:           $AGE"
    if [ "$PORT" != "not-mapped" ]; then
        echo "   SSH:           ssh -i ${SSH_PRIVATE_KEY_PATH} -p $PORT ${USERNAME}@localhost"
        echo "   Port:          $PORT"
        echo "   Port-forward:  $PF_STATUS"
    else
        echo "   Port:          not allocated"
    fi
    echo ""
done <<< "$PODS"

echo "═══════════════════════════════════════════════════════════════"

