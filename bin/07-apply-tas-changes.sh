#!/usr/bin/env bash
# ABOUTME: Applies TAS changes and deploys to BOSH
# ABOUTME: Triggers Ops Manager to deploy TAS

set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Set up logging
LOG_DIR="${CUR_DIR}/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/07-apply-tas-changes-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"
echo "Started at: $(date)"
echo ""

# Get Ops Manager credentials
opsman_hostname="opsman.tas.vcf.lab"
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_decryption_passphrase=$(op read "op://Private/opsman.tas.vcf.lab/password")

# Create env file
export ENV_FILE
ENV_FILE=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/env/env.yml" \
  --var="ops_manager_hostname=$opsman_hostname" \
  --var="opsman_username=$opsman_username" \
  --var="opsman_password=\"$opsman_password\"" \
  --var="opsman_decryption_passphrase=\"$opsman_decryption_passphrase\"" \
  > "$ENV_FILE"

echo "=== Applying TAS Changes ==="
echo ""
echo "Pending changes:"
om --env "$ENV_FILE" pending-changes

echo ""
read -p "Proceed with deployment? (yes/no): " PROCEED

if [[ "$PROCEED" != "yes" ]]; then
  echo "Deployment cancelled"
  rm -f "$ENV_FILE"
  exit 0
fi

echo ""
echo "Starting deployment..."
echo "This will take 30-60 minutes for Small Footprint TAS"
echo ""

om --env "$ENV_FILE" apply-changes \
  --skip-deploy-products=pivotal-telemetry-om

# Cleanup
rm -f "$ENV_FILE"

echo ""
echo "===================================================================="
echo "TAS deployment completed successfully!"
echo "===================================================================="
echo ""
echo "Access TAS:"
echo "  System Domain: https://api.sys.tas.vcf.lab"
echo "  Apps Manager:  https://apps.sys.tas.vcf.lab"
echo ""
echo "Login as admin:"
echo "  cf login -a https://api.sys.tas.vcf.lab --skip-ssl-validation"
echo ""
