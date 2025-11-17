#!/bin/bash
# One-time setup for IREE TensorWave Cluster
set -euo pipefail

echo "════════════════════════════════════════════════════════════════"
echo "  IREE TensorWave Cluster - Interactive Pod Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."
echo ""

MISSING=()

# Check kubectl
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl installed"
else
    echo "❌ kubectl NOT installed"
    MISSING+=("kubectl")
fi

# Check jq
if command -v jq &> /dev/null; then
    echo "✅ jq installed"
else
    echo "❌ jq NOT installed"
    MISSING+=("jq")
fi

# Check krew
if kubectl krew version &> /dev/null; then
    echo "✅ krew installed"
else
    echo "❌ krew NOT installed"
    MISSING+=("krew")
fi

# Check oidc-login
if kubectl oidc-login --version &> /dev/null; then
    echo "✅ oidc-login installed"
else
    echo "❌ oidc-login NOT installed"
    MISSING+=("oidc-login")
fi

# Check kubeswitch
if command -v switch &> /dev/null || command -v switcher &> /dev/null; then
    echo "✅ kubeswitch installed"
else
    echo "⚠️  kubeswitch NOT installed (optional but recommended)"
fi

# Check SSH key
if [ -f ~/.ssh/id_rsa.pub ]; then
    echo "✅ SSH public key found (~/.ssh/id_rsa.pub)"
else
    echo "❌ SSH public key NOT found (~/.ssh/id_rsa.pub)"
    MISSING+=("ssh-key")
fi

# Check kubeconfig
if [ -f ~/.kube/configs/tw-tus1-bm-private-sso.conf ]; then
    echo "✅ IREE cluster kubeconfig found"
else
    echo "⚠️  IREE cluster kubeconfig NOT found at ~/.kube/configs/tw-tus1-bm-private-sso.conf"
    echo "   (Will check if KUBECONFIG is set...)"
    if [ -n "${KUBECONFIG:-}" ]; then
        echo "   ✅ KUBECONFIG is set to: $KUBECONFIG"
    else
        echo "   ❌ KUBECONFIG not set"
        MISSING+=("kubeconfig")
    fi
fi

echo ""

# Show missing items
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "❌ Missing required tools. Please install:"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    for item in "${MISSING[@]}"; do
        case $item in
            kubectl)
                echo "📦 kubectl:"
                echo "   https://kubernetes.io/docs/tasks/tools/install-kubectl/"
                echo ""
                ;;
            jq)
                echo "📦 jq:"
                echo "   sudo apt-get install jq  # or brew install jq on Mac"
                echo ""
                ;;
            krew)
                echo "📦 krew:"
                echo "   https://krew.sigs.k8s.io/docs/user-guide/setup/install/"
                echo ""
                ;;
            oidc-login)
                echo "📦 oidc-login:"
                echo "   kubectl krew install oidc-login"
                echo ""
                ;;
            ssh-key)
                echo "📦 SSH key:"
                echo "   ssh-keygen -t rsa -b 4096 -C \"your.email@amd.com\""
                echo ""
                ;;
            kubeconfig)
                echo "📦 IREE cluster kubeconfig:"
                echo "   Download from: https://amd.atlassian.net/wiki/spaces/SHARK/pages/1109886532/Shark+Platform+TensorWave+Clusters#TW-TUS1-BM-PRIVATE"
                echo "   Save to: ~/.kube/configs/tw-tus1-bm-private-sso.conf"
                echo "   Then: export KUBECONFIG=~/.kube/configs/tw-tus1-bm-private-sso.conf"
                echo ""
                ;;
        esac
    done
    
    echo "After installing missing tools, run this script again."
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "✅ All prerequisites met!"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if config exists
if [ -f config.json ]; then
    echo "✅ config.json already exists"
    echo ""
    echo "Current configuration:"
    cat config.json | jq .
    echo ""
    echo "To modify, edit config.json directly"
else
    echo "📝 Creating config.json from template..."
    echo ""
    echo "Please enter your AMD username (e.g., mravisha, zyin):"
    read -r USERNAME
    
    # Create config from template
    sed "s/YOUR_USERNAME/$USERNAME/g" config.json.example > config.json
    
    echo ""
    echo "✅ config.json created!"
    echo ""
    echo "Configuration:"
    cat config.json | jq .
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🎯 Next Steps:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1. Authenticate with cluster:"
echo "   kubectl get namespaces"
echo "   (This will open a browser for Okta SSO login)"
echo ""
echo "2. Create your PVC (one-time):"
echo "   ./create-pvc.sh"
echo ""
echo "3. Connect to your pod:"
echo "   ./connect.sh"
echo ""
echo "════════════════════════════════════════════════════════════════"

