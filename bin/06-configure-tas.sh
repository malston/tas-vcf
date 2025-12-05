#!/usr/bin/env bash
# ABOUTME: Configures TAS tile for VCF deployment
# ABOUTME: Retrieves secrets from 1Password and interpolates into TAS config

set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Set up logging
LOG_DIR="${CUR_DIR}/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/06-configure-tas-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Log file: $LOG_FILE"
echo "Started at: $(date)"
echo ""

# Get sensitive values from 1Password
nsxt_password=$(op read "op://Private/nsx01.vcf.lab/password")
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_decryption_passphrase=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_hostname="opsman.tas.vcf.lab"
nsxt_username="admin"

# CredHub encryption key management
credhub_key_file="${CUR_DIR}/../foundations/${FOUNDATION}/state/credhub-key.txt"

if [[ ! -f "$credhub_key_file" ]]; then
  echo "=================================================================================================="
  echo "WARNING: CredHub encryption key file does not exist: $credhub_key_file"
  echo "=================================================================================================="
  echo "Attempting to retrieve from 1Password..."

  # Try to get from 1Password first
  if credhub_key_from_1p=$(op read "op://Private/TAS VCF Lab - Credhub Encryption Key/password" 2>/dev/null); then
    echo "✓ Retrieved CredHub key from 1Password"
    echo "$credhub_key_from_1p" > "$credhub_key_file"
    chmod 600 "$credhub_key_file"
  else
    echo "✗ Key not found in 1Password, generating new key..."
    echo "  You will need to save this to 1Password: op://Private/TAS VCF Lab - Credhub Encryption Key"
    openssl rand -base64 32 > "$credhub_key_file"
    chmod 600 "$credhub_key_file"
    echo ""
    echo "NEW KEY GENERATED: $(cat "$credhub_key_file")"
    echo "Save this to 1Password NOW before continuing!"
    echo ""
    read -p "Press Enter after saving to 1Password..."
  fi
fi

credhub_encryption_key=$(cat "$credhub_key_file")
echo "Using CredHub encryption key from: $credhub_key_file"

# Get certificates from Terraform outputs
cd "${CUR_DIR}/../terraform/certs"
tas_system_cert=$(terraform output -raw tas_system_cert 2>/dev/null || echo "")
tas_system_key=$(terraform output -raw tas_system_key 2>/dev/null || echo "")
tas_apps_cert=$(terraform output -raw tas_apps_cert 2>/dev/null || echo "")
tas_apps_key=$(terraform output -raw tas_apps_key 2>/dev/null || echo "")
ca_cert=$(terraform output -raw ca_cert 2>/dev/null || echo "")

if [[ -z "$tas_system_cert" ]] || [[ -z "$tas_apps_cert" ]]; then
  echo "ERROR: Certificates not found. Run: cd terraform/certs && terraform apply"
  exit 1
fi

# Create temporary vars file with interpolated secrets
export VARS_FILES
VARS_FILES=$(mktemp)

om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/vars/tas.yml" \
  --var="nsxt_username=$nsxt_username" \
  --var="nsxt_password=$nsxt_password" \
  --var="tas_system_cert_pem=$tas_system_cert" \
  --var="tas_system_key_pem=$tas_system_key" \
  --var="tas_apps_cert_pem=$tas_apps_cert" \
  --var="tas_apps_key_pem=$tas_apps_key" \
  --var="uaa_service_provider_cert=$tas_system_cert" \
  --var="uaa_service_provider_key=$tas_system_key" \
  --var="trusted_certificates=$ca_cert" \
  --var="credhub_encryption_key=$credhub_encryption_key" \
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

export TAS_CONFIG_FILE="${CUR_DIR}/../foundations/${FOUNDATION}/config/tas.yml"

# Call the configure script
"${CUR_DIR}/../scripts/configure-tas.sh"

# Cleanup temp files
rm -f "$VARS_FILES" "$ENV_FILE"

echo ""
echo "===================================================================="
echo "TAS configuration applied successfully!"
echo "===================================================================="
echo ""
echo "Next steps:"
echo "  1. Review pending changes: om --env <env-file> pending-changes"
echo "  2. Apply changes: bin/07-apply-tas-changes.sh"
echo ""
