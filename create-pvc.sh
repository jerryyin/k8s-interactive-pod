#!/bin/bash
# Create PersistentVolumeClaim for the IREE cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found. Run ./setup.sh first!"
    exit 1
fi

NAMESPACE=$(jq -r '.namespace' "$CONFIG_FILE")
PVC_NAME=$(jq -r '.pvc' "$CONFIG_FILE")

echo "════════════════════════════════════════════════════════════════"
echo "  Creating PVC: $PVC_NAME"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if PVC already exists
if kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "✅ PVC '$PVC_NAME' already exists in namespace '$NAMESPACE'"
    kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"
    exit 0
fi

# Create PVC YAML
PVC_YAML=$(mktemp)
cat > "$PVC_YAML" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF

echo "Creating PVC with 100Gi storage..."
kubectl apply -f "$PVC_YAML"
rm "$PVC_YAML"

echo ""
echo "⏳ Waiting for PVC to be bound..."
if kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" -n "$NAMESPACE" --timeout=60s; then
    echo ""
    echo "✅ PVC created successfully!"
    echo ""
    kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"
else
    echo ""
    echo "⚠️  PVC created but not yet bound. This may take a few moments."
    echo "   Check status with: kubectl get pvc $PVC_NAME -n $NAMESPACE"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  PVC Ready! You can now run: ./connect.sh"
echo "════════════════════════════════════════════════════════════════"

