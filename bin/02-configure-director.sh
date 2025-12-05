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

# Build trusted certificates bundle (vSphere CA + TAS CA)
echo "Building trusted certificates bundle..."

# Fetch NSX-T Manager certificate
# echo "Fetching NSX-T Manager certificate..."
# nsx_host="nsx01.vcf.lab"

# # Get the certificate chain and extract the root CA (last certificate in chain)
# nsx_ca=$(openssl s_client -connect "${nsx_host}:443" -showcerts < /dev/null 2>/dev/null | \
#   awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print} /END CERTIFICATE/ {cert=cert $0 "\n"; next} {cert=cert $0 "\n"}' | \
#   awk 'BEGIN{RS="-----END CERTIFICATE-----\n"; ORS=""} {cert=$0 "-----END CERTIFICATE-----\n"} END{print cert}')

# if [[ -z "$nsx_ca" ]]; then
#   echo "ERROR: Failed to fetch NSX-T Manager certificate from ${nsx_host}"
#   echo "Please check network connectivity and NSX-T Manager availability"
#   exit 1
# fi

# echo "✓ Successfully retrieved NSX-T Manager certificate from ${nsx_host}"

# Fetch vSphere Root CA from vCenter (signs NSX-T Manager certificate)
echo "Fetching vSphere Root CA from vCenter..."
vcenter_host="vc01.vcf.lab"

# Get the certificate chain and extract the root CA (last certificate in chain)
vsphere_ca=$(openssl s_client -connect "${vcenter_host}:443" -showcerts < /dev/null 2>/dev/null | \
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print} /END CERTIFICATE/ {cert=cert $0 "\n"; next} {cert=cert $0 "\n"}' | \
  awk 'BEGIN{RS="-----END CERTIFICATE-----\n"; ORS=""} {cert=$0 "-----END CERTIFICATE-----\n"} END{print cert}')

if [[ -z "$vsphere_ca" ]]; then
  echo "ERROR: Failed to fetch vSphere Root CA from ${vcenter_host}"
  echo "Please check network connectivity and vCenter availability"
  exit 1
fi

echo "✓ Successfully retrieved vSphere Root CA from ${vcenter_host}"

# Get TAS Homelab CA from Terraform
cd "${CUR_DIR}/../terraform/certs"
tas_ca=$(terraform output -raw ca_cert 2>/dev/null || echo "")
cd - > /dev/null

if [[ -z "$tas_ca" ]]; then
  echo "ERROR: TAS CA certificate not found. Run: cd terraform/certs && terraform apply"
  exit 1
fi

# Combine both CAs into a single bundle
trusted_certs="$vsphere_ca
$tas_ca"

# Create temporary vars file with interpolated secrets
export VARS_FILES
VARS_FILES=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/vars/director.yml" \
  --var="vcenter_username=$vcenter_username" \
  --var="vcenter_password=$vcenter_password" \
  --var="nsxt_username=$nsxt_username" \
  --var="nsxt_password=$nsxt_password" \
  --var="ops_manager_hostname=$opsman_hostname" \
  --var="trusted_certificates=$trusted_certs" \
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
