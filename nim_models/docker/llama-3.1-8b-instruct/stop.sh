#!/usr/bin/env bash
# =============================================================================
# Stop Meta Llama-3.1-8B-Instruct NVIDIA NIM & Free GPU Memory
# =============================================================================
set -euo pipefail

CONTAINER_NAME="llama-3.1-8b"

echo "🛑 Oprire container '${CONTAINER_NAME}' si eliberare memorie GPU..."

if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  docker rm -f "$CONTAINER_NAME"
  echo "✅ Containerul '${CONTAINER_NAME}' a fost oprit si sters."
else
  echo "ℹ️ Containerul '${CONTAINER_NAME}' nu este activ."
fi

if command -v nvidia-smi &> /dev/null; then
  echo "📊 Stare curenta memorie GPU:"
  nvidia-smi --query-gpu=name,memory.used,memory.free --format=csv,noheader
fi
