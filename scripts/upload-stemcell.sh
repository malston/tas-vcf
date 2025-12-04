#!/usr/bin/env bash
# ABOUTME: Uploads stemcell to Ops Manager
# ABOUTME: Expects ENV_FILE and STEMCELL_FILE to be set

set -euo pipefail

if [[ -z "${ENV_FILE:-}" ]]; then
  echo "ERROR: ENV_FILE must be set"
  exit 1
fi

if [[ -z "${STEMCELL_FILE:-}" ]]; then
  echo "ERROR: STEMCELL_FILE must be set"
  exit 1
fi

if [[ ! -f "$STEMCELL_FILE" ]]; then
  echo "ERROR: Stemcell file not found: $STEMCELL_FILE"
  exit 1
fi

echo "Uploading stemcell: $STEMCELL_FILE"
echo "This may take a few minutes..."

om --env "$ENV_FILE" upload-stemcell \
  --stemcell "$STEMCELL_FILE"

echo "Stemcell uploaded successfully!"

# List available stemcells
echo ""
echo "Available stemcells:"
om --env "$ENV_FILE" curl -p /api/v0/stemcell_assignments | \
  jq -r '.products[] | "\(.guid): \(.staged_stemcell_version // "none")"'
