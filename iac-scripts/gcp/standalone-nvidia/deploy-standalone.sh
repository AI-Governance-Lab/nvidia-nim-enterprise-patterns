#!/bin/bash

# A comprehensive list of global zones hosting Nvidia L4 GPUs (G2 Machine Families)
ZONES=(
  "us-central1-a"
  "us-central1-b"
  "us-central1-c"
  "us-east1-c"
  "us-east4-a"
  "us-east4-b"
  "us-west1-a"
  "us-west1-b"
  "us-west4-a"
  "us-west4-b"
  "europe-west1-b"
  "europe-west1-c"
  "europe-west4-a"
  "europe-west4-b"
)

for ZONE in "${ZONES[@]}"; do
  # Automatically extract region (e.g. "us-central1-a" -> "us-central1")
  REGION=$(echo "$ZONE" | cut -d'-' -f1-2)

  echo "========================================================"
  echo "🔍 Trying Zone: $ZONE  |  Region: $REGION"
  echo "========================================================"

  # Execute terraform apply targeting both matching region and zone
  terraform apply -var="zone=$ZONE" -var="region=$REGION" -auto-approve

  if [ $? -eq 0 ]; then
    echo ""
    echo "========================================================"
    echo "🚀 SUCCESS! Your Standalone GPU VM is running!"
    echo "📍 Zone:   $ZONE"
    echo "📍 Region: $REGION"
    echo "========================================================"
    exit 0
  else
    echo ""
    echo "⚠️ Capacity exhausted in $ZONE. Sweeping next target..."
    echo ""
  fi
done

echo "❌ ERROR: All L4-enabled zones globally are currently out of capacity. Please try again later."
exit 1
