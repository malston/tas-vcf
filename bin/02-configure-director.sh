#!/usr/bin/env bash
# ABOUTME: Configures BOSH Director for VCF deployment
# ABOUTME: Retrieves secrets from 1Password and interpolates into director config

set -e

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Set up logging
LOG_DIR="${CUR_DIR}/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/02-configure-director-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"
echo "Started at: $(date)"
echo ""

# Get sensitive values from 1Password
vcenter_password=$(op read "op://Private/vc01.vcf.lab/password")
nsxt_password=$(op read "op://Private/nsx01.vcf.lab/password")
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_decryption_passphrase="$opsman_password"
opsman_hostname="opsman.tas.vcf.lab"
vcenter_username="administrator@vsphere.local"
nsxt_username="admin"

# Create temporary vars file with interpolated secrets
export VARS_FILES
VARS_FILES=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/vars/director.yml" \
  --var="vcenter_username=$vcenter_username" \
  --var="vcenter_password=$vcenter_password" \
  --var="nsxt_username=$nsxt_username" \
  --var="nsxt_password=$nsxt_password" \
  --var="ops_manager_hostname=$opsman_hostname" \
  > "$VARS_FILES"

# Set env file with Ops Manager connection details
export ENV_FILE
ENV_FILE=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/env/env.yml" \
  --var="ops_manager_hostname=$opsman_hostname" \
  --var="opsman_username=$opsman_username" \
  --var="opsman_password=\"$opsman_password\"" \
  --var="opsman_decryption_passphrase=\"$opsman_decryption_passphrase\"" \
  > "$ENV_FILE"

export DIRECTOR_CONFIG_FILE="${CUR_DIR}/../foundations/${FOUNDATION}/config/director.yml"

# Call the configure script
"${CUR_DIR}/../scripts/configure-director.sh"

# Cleanup temp files
rm -f "$VARS_FILES" "$ENV_FILE"

echo "ENV_FILE used: $ENV_FILE"
echo "DIRECTOR_CONFIG_FILE used: $DIRECTOR_CONFIG_FILE"

echo ""
echo "===================================================================="
echo "Director configuration applied successfully!"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  1. Review pending changes: om --env <env-file> pending-changes"
echo "  2. Apply changes: om --env <env-file> apply-changes"
echo ""
