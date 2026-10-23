#!/usr/bin/env bash
# =============================================================================
# Quick Inference Test Script for OpenAI-compatible NIM Endpoints
# =============================================================================
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-8000}"
PROMPT="${3:-Explica in 2 propozitii ce este un Large Language Model (LLM).}"

API_URL="http://${HOST}:${PORT}/v1"

echo "🔍 Detectare model activ la ${API_URL}/models..."
MODELS_JSON=$(curl -s "${API_URL}/models" || echo '{"data":[]}')
MODEL_ID=$(echo "$MODELS_JSON" | grep -o '"id": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || echo "")

if [[ -z "$MODEL_ID" ]]; then
  echo "⚠️ Nu s-a putut detecta automat modelul. Se foloseste fallback: deepseek-ai/deepseek-r1-distill-llama-8b"
  MODEL_ID="deepseek-ai/deepseek-r1-distill-llama-8b"
else
  echo "✅ Model detectat: ${MODEL_ID}"
fi

echo ""
echo "🚀 Trimitere prompt: \"${PROMPT}\""
echo "-----------------------------------------------------------------"

curl -s -X POST "${API_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_ID}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"${PROMPT}\"}
    ],
    \"temperature\": 0.3,
    \"max_tokens\": 250
  }" | (command -v jq &>/dev/null && jq -r '.choices[0].message.content // .' || cat)

echo ""
echo "-----------------------------------------------------------------"
echo "✅ Test finalizat!"
