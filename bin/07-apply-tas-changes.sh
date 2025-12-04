#!/usr/bin/env bash
# ABOUTME: Applies TAS changes and deploys to BOSH
# ABOUTME: Triggers Ops Manager to deploy TAS

set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

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

echo "=== Applying TAS Changes ==="
echo ""
echo "Pending changes:"
om --env "$ENV_FILE" pending-changes --format json | jq -r '.product_changes[] | "\(.action): \(.guid)"'

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
