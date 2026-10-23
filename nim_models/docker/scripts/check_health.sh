#!/usr/bin/env bash
# =============================================================================
# Health Check Polling Script for NVIDIA NIM Containers
# =============================================================================
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-8000}"
MAX_WAIT_SECONDS="${3:-600}"

HEALTH_URL="http://${HOST}:${PORT}/v1/health/ready"

echo "⏳ Asteptare pornire NVIDIA NIM la ${HEALTH_URL} (Timeout: ${MAX_WAIT_SECONDS}s)..."

START_TIME=$(date +%s)

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  if [[ $ELAPSED -ge $MAX_WAIT_SECONDS ]]; then
    echo ""
    echo "❌ TIMEOUT: Serviciul NIM nu a devenit ready dupa ${MAX_WAIT_SECONDS} secunde."
    echo "💡 Sugestie: Verifica logurile containerului cu 'docker logs -f <nume_container>'."
    exit 1
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo ""
    echo "🎉 SUCCESS: Endpoint-ul NIM este READY (HTTP 200) dupa ${ELAPSED} secunde!"
    
    # Afiseaza lista modelelor incarcate
    MODELS=$(curl -s "http://${HOST}:${PORT}/v1/models" 2>/dev/null || echo "{}")
    echo "📦 Modele detectate: $MODELS"
    exit 0
  fi

  printf "."
  sleep 5
done
