#!/usr/bin/env bash
# ABOUTME: Uploads TAS tile to Ops Manager
# ABOUTME: Retrieves credentials and calls upload script

set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Tile location
export TAS_TILE="${TAS_TILE:-/tmp/srt-6.0.6-build.2.pivotal}"

# Get Ops Manager credentials
opsman_hostname="opsman.tas.vcf.lab"
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")

# Create env file
export ENV_FILE
ENV_FILE=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/env/env.yml" \
  --var="ops_manager_hostname=$opsman_hostname" \
  --var="opsman_username=$opsman_username" \
  --var="opsman_password=\"$opsman_password\"" \
  > "$ENV_FILE"

# Call upload script
"${CUR_DIR}/../scripts/upload-tile.sh"

# Cleanup
rm -f "$ENV_FILE"

echo ""
echo "===================================================================="
echo "TAS tile uploaded successfully!"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  1. Upload stemcell: bin/05-upload-stemcell.sh"
echo "  2. Configure TAS: bin/06-configure-tas.sh"
echo ""
