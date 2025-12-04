#!/usr/bin/env bash
# ABOUTME: Uploads product tile to Ops Manager
# ABOUTME: Expects ENV_FILE and TAS_TILE to be set

set -euo pipefail

if [[ -z "${ENV_FILE:-}" ]]; then
  echo "ERROR: ENV_FILE must be set"
  exit 1
fi

if [[ -z "${TAS_TILE:-}" ]]; then
  echo "ERROR: TAS_TILE must be set"
  exit 1
fi

if [[ ! -f "$TAS_TILE" ]]; then
  echo "ERROR: Tile file not found: $TAS_TILE"
  exit 1
fi

echo "Uploading tile: $TAS_TILE"
echo "This may take several minutes..."

om --env "$ENV_FILE" upload-product \
  --product "$TAS_TILE"

echo "Tile uploaded successfully!"

# Get product name and version
product_name=$(om --env "$ENV_FILE" available-products --format json | \
  jq -r '.[] | select(.name | startswith("srt") or startswith("cf")) | .name' | head -1)
product_version=$(om --env "$ENV_FILE" available-products --format json | \
  jq -r '.[] | select(.name | startswith("srt") or startswith("cf")) | .version' | head -1)

echo "Staging product: $product_name version $product_version"

om --env "$ENV_FILE" stage-product \
  --product-name "$product_name" \
  --product-version "$product_version"

echo "Product staged successfully!"
