#!/usr/bin/env bash
# ABOUTME: Configures TAS tile using om configure-product
# ABOUTME: Expects ENV_FILE, VARS_FILES, and TAS_CONFIG_FILE to be set

set -euo pipefail

if [[ -z "${ENV_FILE:-}" ]]; then
  echo "ERROR: ENV_FILE must be set"
  exit 1
fi

if [[ -z "${VARS_FILES:-}" ]]; then
  echo "ERROR: VARS_FILES must be set"
  exit 1
fi

if [[ -z "${TAS_CONFIG_FILE:-}" ]]; then
  echo "ERROR: TAS_CONFIG_FILE must be set"
  exit 1
fi

if [[ ! -f "$TAS_CONFIG_FILE" ]]; then
  echo "ERROR: TAS config file not found: $TAS_CONFIG_FILE"
  exit 1
fi

echo "Configuring TAS tile..."

om --env "$ENV_FILE" configure-product \
  --config "$TAS_CONFIG_FILE" \
  --vars-file "$VARS_FILES"

echo "TAS tile configured successfully!"

# Show pending changes
echo ""
echo "Pending changes:"
om --env "$ENV_FILE" pending-changes --format json | jq -r '.product_changes[] | "\(.action): \(.guid)"'
