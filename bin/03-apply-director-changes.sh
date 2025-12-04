#!/usr/bin/env bash
# ABOUTME: Applies pending BOSH Director changes
# ABOUTME: Runs pre-deploy checks and deploys the director

set -e

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Get Ops Manager credentials
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_decryption_passphrase="$opsman_password"
opsman_hostname="opsman.tas.vcf.lab"

# Create env file
ENV_FILE=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/env/env.yml" \
  --var="ops_manager_hostname=$opsman_hostname" \
  --var="opsman_username=$opsman_username" \
  --var="opsman_password=$opsman_password" \
  --var="opsman_decryption_passphrase=$opsman_decryption_passphrase" \
  > "$ENV_FILE"

echo "===================================================================="
echo "Running pre-deploy check..."
echo "===================================================================="
om --env "$ENV_FILE" pre-deploy-check

echo ""
echo "===================================================================="
echo "Applying BOSH Director changes..."
echo "===================================================================="
echo "This will take 15-30 minutes."
echo ""

om --env "$ENV_FILE" apply-changes --skip-deploy-products

# Cleanup
rm -f "$ENV_FILE"

echo ""
echo "===================================================================="
echo "Director deployment completed!"
echo "===================================================================="
echo ""
