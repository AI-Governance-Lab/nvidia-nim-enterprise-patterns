#!/usr/bin/env bash
# =============================================================================
# Automated Sync Script: Local Workstation -> Remote GPU VM
# Supports both Docker microservices and Kubernetes (K3s) manifests/Helm charts.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_MODE="all" # Options: all, docker, k3s
CUSTOM_VM=""
CUSTOM_ZONE=""

usage() {
  cat <<HELP
Usage: $(basename "$0") [OPTIONS]

Sync local nim_models assets (Docker, K3s, and environment configurations) to the active GCP GPU VM.

Options:
  --all           Sync all nim_models directories (Docker & K3s) [Default]
  --docker        Sync only the Docker deployment assets
  --k3s           Sync only the K3s / Helm deployment assets
  --vm NAME       Explicitly specify the remote VM name
  --zone ZONE     Explicitly specify the GCP zone
  -h, --help      Show this help message

Examples:
  ./scripts/sync_to_vm.sh
  ./scripts/sync_to_vm.sh --docker
  ./scripts/sync_to_vm.sh --vm gpu-worker-c67t --zone us-central1-a
HELP
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) TARGET_MODE="all"; shift ;;
    --docker) TARGET_MODE="docker"; shift ;;
    --k3s) TARGET_MODE="k3s"; shift ;;
    --vm) CUSTOM_VM="$2"; shift 2 ;;
    --zone) CUSTOM_ZONE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "❌ Unknown option: $1"; usage ;;
  esac
done

echo "================================================================="
echo "  NVIDIA NIM Enterprise Patterns - Remote VM Synchronizer"
echo "================================================================="

# 1. Discover active VM
if [[ -n "$CUSTOM_VM" && -n "$CUSTOM_ZONE" ]]; then
  VM_NAME="$CUSTOM_VM"
  VM_ZONE="$CUSTOM_ZONE"
else
  echo "🔍 Auto-discovering running GPU VM via gcloud..."
  VM_NAME=$(gcloud compute instances list --filter="name~'gpu-worker' AND status=RUNNING" --format="get(name)" --limit=1)
  VM_ZONE=$(gcloud compute instances list --filter="name~'gpu-worker' AND status=RUNNING" --format="get(zone)" --limit=1)
fi

if [[ -z "$VM_NAME" || -z "$VM_ZONE" ]]; then
  echo "❌ Error: No running 'gpu-worker' instances found on GCP!"
  echo "👉 Provision one first with: cd iac-scripts/gcp/mig-nvidia && terraform apply"
  exit 1
fi

echo "✅ Target VM : ${VM_NAME}"
echo "📍 GCP Zone  : ${VM_ZONE}"
echo "📦 Mode      : ${TARGET_MODE}"
echo "-----------------------------------------------------------------"

# 2. Sync nim_models based on selected mode
case "$TARGET_MODE" in
  docker)
    echo "📤 Transferring Docker patterns (nim_models/docker)..."
    gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --quiet --command="mkdir -p ~/nim_models"
    gcloud compute scp --recurse "${REPO_ROOT}/nim_models/docker" "${VM_NAME}:~/nim_models/" --zone="$VM_ZONE" --quiet
    ;;
  k3s)
    echo "📤 Transferring K3s patterns (nim_models/k3s)..."
    gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --quiet --command="mkdir -p ~/nim_models"
    gcloud compute scp --recurse "${REPO_ROOT}/nim_models/k3s" "${VM_NAME}:~/nim_models/" --zone="$VM_ZONE" --quiet
    ;;
  all)
    echo "📤 Transferring full nim_models directory (Docker + K3s)..."
    gcloud compute scp --recurse "${REPO_ROOT}/nim_models" "${VM_NAME}:~" --zone="$VM_ZONE" --quiet
    ;;
esac

# 3. Synchronize .env with NGC_API_KEY
if [[ -f "${REPO_ROOT}/.env" ]]; then
  echo "🔐 Synchronizing .env credentials to remote VM..."
  gcloud compute scp "${REPO_ROOT}/.env" "${VM_NAME}:~/nim_models/docker/.env" --zone="$VM_ZONE" --quiet
elif [[ -f "${REPO_ROOT}/nim_models/docker/.env" ]]; then
  echo "🔐 Synchronizing nim_models/docker/.env credentials to remote VM..."
  gcloud compute scp "${REPO_ROOT}/nim_models/docker/.env" "${VM_NAME}:~/nim_models/docker/.env" --zone="$VM_ZONE" --quiet
fi

# 4. Ensure script executable permissions on the remote host
echo "🔧 Setting executable permissions on remote scripts..."
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --quiet --command="
  find ~/nim_models -type f -name '*.sh' -exec chmod +x {} +
"

echo ""
echo "🎉 Synchronization complete!"
echo "-----------------------------------------------------------------"
echo "🚀 Quick execution commands on ${VM_NAME}:"
echo "   - Run DeepSeek-R1 (Docker) : gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command='cd ~/nim_models/docker/deepseek-r1-distill-8b && ./run.sh'"
echo "   - Run Llama-3.1-8B (Docker): gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command='cd ~/nim_models/docker/llama-3.1-8b-instruct && ./run.sh'"
echo "   - Check GPU Status         : gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command='nvidia-smi'"
echo "-----------------------------------------------------------------"
