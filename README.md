# IREE TensorWave Cluster - Interactive Development Pods

**Get a GPU development environment in the IREE cluster in 3 commands.**

```bash
./setup.sh      # One-time setup
./create-pvc.sh # Create your storage (one-time)
./connect.sh    # Connect to your pod!
```

## What Is This?

This gives you an **SSH-accessible development pod** in the IREE TensorWave Kubernetes cluster with:
- ✅ AMD GPU access
- ✅ Persistent storage (your files survive pod restarts)
- ✅ Root access (install whatever you need)
- ✅ Pre-configured IREE development image

## Prerequisites

Before you start, you need:

1. **Access to IREE cluster** - Follow the [onboarding guide](https://amd.atlassian.net/wiki/spaces/SHARK/pages/1137421935/Shark+Platform+TensorWave+Cluster+Onboarding)
2. **Tools installed** (setup.sh will check):
   - kubectl
   - jq
   - krew
   - oidc-login (for SSO authentication)
3. **Kubeconfig downloaded** - Get it [here](https://amd.atlassian.net/wiki/spaces/SHARK/pages/1109886532/Shark+Platform+TensorWave+Clusters#TW-TUS1-BM-PRIVATE)
4. **SSH key** - You probably already have one at `~/.ssh/id_rsa.pub`

Don't worry - `./setup.sh` will check everything and tell you what's missing!

## Quick Start

### Step 1: Setup (One-Time)

```bash
git clone <this-repo>
cd k8s-interactive-pod
./setup.sh
```

This will:
- ✅ Check all prerequisites
- ✅ Create `config.json` (just enter your AMD username when prompted)
- ✅ Tell you what to do next

### Step 2: Create Storage (One-Time)

```bash
./create-pvc.sh
```

This creates your 100GB persistent storage in the cluster.

### Step 3: Connect!

```bash
./connect.sh
```

That's it! You're now SSH'd into your development pod. 🎉

## What You Get

Once connected, you have:
- **AMD GPU** (1 GPU, configurable)
- **IREE development image** (ghcr.io/nod-ai/ossci-gitops/iree-dev:main)
- **Root access** (`sudo` with no password)
- **Pre-installed**: git, vim, curl, zsh, tmux, and IREE build tools
- **Persistent storage** at `/<your-username>/` (survives pod deletion)
- **Ephemeral workspace** at `/home/<your-username>/` (fresh each pod)

## Common Tasks

### Connect to Existing Pod

```bash
./connect.sh
```

If you have multiple pods, it will show you a menu to choose.

### Create Another Pod

```bash
./connect.sh --new
```

Useful for running multiple experiments in parallel.

### List Your Pods

```bash
./list-pods.sh
```

Shows all your pods with status, SSH port, and node information.

### Stop Pods

```bash
./stop.sh
```

Interactive menu to delete pods and cleanup port-forwards.

### Use Ephemeral Mode (No PVC)

```bash
./connect.sh --ephemeral
```

Faster startup, but no persistent storage (everything deleted when pod stops).

## Configuration

Edit `config.json` to customize:

```json
{
  "namespace": "iree-dev",                              // IREE namespace
  "pvc": "iree-dev-YOUR_USERNAME-pvc",                 // Your PVC name
  "username": "YOUR_USERNAME",                          // Your AMD username
  "public_ssh_key_path": "~/.ssh/id_rsa.pub",          // Your SSH key
  "docker_image": "ghcr.io/nod-ai/ossci-gitops/iree-dev:main"  // Base image
}
```

### Change Docker Image

Want a different base image? Just edit `docker_image` in `config.json`:

```json
"docker_image": "ghcr.io/nod-ai/ossci-gitops/rocm-dev:main"
```

Or use the official ROCm image:
```json
"docker_image": "rocm/dev-ubuntu-24.04:latest"
```

## Storage Architecture

Your pod has two storage areas:

### 1. Ephemeral: `/home/<username>/`
- **Size**: 10GB
- **Lifetime**: Deleted when pod stops
- **Use for**: Temporary files, builds, experiments

### 2. Persistent: `/<username>/`
- **Size**: 100GB (from your PVC)
- **Lifetime**: Survives pod deletion
- **Use for**: Code, data, important files

**💡 Tip:** Work in `/home/<username>/` but save important stuff to `/<username>/`

## SSH Access

Each pod gets its own port (2222, 2223, etc.):

```bash
# First pod
ssh -p 2222 <username>@localhost

# Second pod
ssh -p 2223 <username>@localhost
```

### Make SSH Easier (Optional)

Add to `~/.ssh/config`:

```
Host dev-pod
  HostName localhost
  Port 2222
  User <your-username>
  ForwardAgent yes
```

Then just: `ssh dev-pod`

## Troubleshooting

### "kubectl: command not found"

Run `./setup.sh` - it will tell you what's missing and how to install it.

### "Permission denied (publickey)"

Check your SSH key path in `config.json`. Default is `~/.ssh/id_rsa.pub`.

### "Pod stuck in ContainerCreating"

First-time pulls the ~10GB IREE image. Takes 10-15 minutes. Check progress:

```bash
kubectl describe pod <pod-name> -n iree-dev
```

### "PVC not found"

Run `./create-pvc.sh` to create your storage.

### Authentication Failed

Re-authenticate with the cluster:

```bash
kubectl get namespaces
```

This will open a browser for Okta SSO login.

## Multiple Pods

**Yes, you can have multiple pods!** Each gets its own SSH port.

```bash
./connect.sh           # Connect to existing pod or create first
./connect.sh --new     # Create second pod
./connect.sh --new     # Create third pod
./list-pods.sh         # See all your pods
```

Use cases:
- Run long training in one pod, debug in another
- Test different configurations in parallel
- Keep stable pod running while experimenting in another

## Advanced

### Customize Pod Resources

Edit `pod-ssh.yml` to request more resources:

```yaml
resources:
  limits:
    amd.com/gpu: 2        # Request 2 GPUs
    memory: "64Gi"        # Request more memory
```

### Add Packages to Image

After connecting, install whatever you need:

```bash
sudo apt-get update
sudo apt-get install <package>
```

Or build a custom image with everything pre-installed and update `docker_image` in `config.json`.

### SSH Agent Forwarding

Already enabled! Your pod can use your laptop's SSH keys for git operations.

Test it:
```bash
ssh -p 2222 <username>@localhost
git clone git@github.com:your/repo.git  # Works!
```

## Links

- [IREE Cluster Onboarding](https://amd.atlassian.net/wiki/spaces/SHARK/pages/1137421935/Shark+Platform+TensorWave+Cluster+Onboarding)
- [TensorWave Cluster Info](https://amd.atlassian.net/wiki/spaces/SHARK/pages/1109886532/Shark+Platform+TensorWave+Clusters)
- [IREE GitHub](https://github.com/iree-org/iree)
