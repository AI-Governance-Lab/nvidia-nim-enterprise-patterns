#!/usr/bin/env bash
# =============================================================================
# Run Meta Llama-3.1-8B-Instruct NVIDIA NIM
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${DOCKER_DIR}/../.." && pwd)"

# Incarca variabilele din .env daca exista
if [[ -f "${DOCKER_DIR}/.env" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "${DOCKER_DIR}/.env"
  set +a
elif [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

CONTAINER_NAME="llama-3.1-8b"
IMAGE_NAME="nvcr.io/nim/meta/llama-3.1-8b-instruct:latest"
PORT="${NIM_PORT:-8000}"
CACHE_DIR="${LOCAL_NIM_CACHE:-$HOME/.cache/nim}"

echo "================================================================="
echo "  Pornire NVIDIA NIM: Meta-Llama-3.1-8B-Instruct"
echo "================================================================="

# 1. Validare NGC_API_KEY
if [[ -z "${NGC_API_KEY:-}" ]]; then
  echo "❌ EROARE: NGC_API_KEY nu este setat!"
  echo "👉 Creeaza fisierul .env in nim_models/docker/ sau exporta cheia:"
  echo "   export NGC_API_KEY=\"nvapi-...\""
  exit 1
fi

# 2. Verificare Docker si GPU runtime
if ! command -v docker &> /dev/null; then
  echo "❌ EROARE: Docker nu este instalat pe acest sistem."
  exit 1
fi

if ! command -v nvidia-smi &> /dev/null; then
  echo "⚠️ AVERTISMENT: nvidia-smi nu a fost gasit. Asigura-te ca driverele GPU sunt instalate."
fi

# 3. Pregatire director cache pe disc
mkdir -p "$CACHE_DIR"
chmod 777 "$CACHE_DIR" 2>/dev/null || true
nvidia-smi -pm 1 2>/dev/null || true
echo "📁 Director Cache local: $CACHE_DIR"

# 4. Autentificare in registrul NVIDIA NGC
echo "🔐 Autentificare in nvcr.io..."
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

# 5. Gestionare containere NIM concurente (eliberare VRAM GPU L4)
OTHER_CONTAINERS=("deepseek-r1" "qwen-coder" "v4-flash")
for other in "${OTHER_CONTAINERS[@]}"; do
  if docker ps --format '{{.Names}}' | grep -Eq "^${other}\$"; then
    echo "⚠️ S-a detectat un alt container NIM activ: '${other}'."
    echo "🛑 Oprire '${other}' pentru a elibera memoria GPU VRAM..."
    docker rm -f "$other" > /dev/null
  fi
done

# Daca propriul container ruleaza deja, il recream curat
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  echo "🔄 Se opreste si se sterge containerul anterior '${CONTAINER_NAME}'..."
  docker rm -f "$CONTAINER_NAME" > /dev/null
fi

# 6. Lansare container NIM
echo "🚀 Lansare container '${CONTAINER_NAME}' pe portul ${PORT}..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --runtime=nvidia \
  --gpus all \
  --ipc=host \
  --shm-size=16g \
  -e NGC_API_KEY="$NGC_API_KEY" \
  -v "${CACHE_DIR}:/opt/nim/.cache" \
  -p "${PORT}:8000" \
  --restart unless-stopped \
  "$IMAGE_NAME"

echo ""
echo "✅ Containerul a fost pornit cu succes in fundal (detached mode)!"
echo "-----------------------------------------------------------------"
echo "📜 Pentru monitorizarea logurilor de descarcare si compilare:"
echo "   docker logs -f ${CONTAINER_NAME}"
echo ""
echo "🔍 Pentru verificarea starii de disponibilitate:"
echo "   curl -s http://localhost:${PORT}/v1/health/ready"
echo "-----------------------------------------------------------------"
