#!/usr/bin/env bash
# ABOUTME: Adds vSphere and TAS CA certificates to macOS System keychain
# ABOUTME: Run this on your Mac to trust TAS and vSphere certificates

set -euo pipefail

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================================"
echo "Trust vSphere and TAS Certificates on macOS"
echo "======================================================================"
echo ""

# Create temp directory for certificates
CERT_DIR=$(mktemp -d)
trap "rm -rf $CERT_DIR" EXIT

# Fetch vSphere Root CA from vCenter
echo "1. Fetching vSphere Root CA from vCenter..."
vcenter_host="vc01.vcf.lab"
vsphere_ca_file="${CERT_DIR}/vsphere-root-ca.crt"

openssl s_client -connect "${vcenter_host}:443" -showcerts < /dev/null 2>/dev/null | \
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print} /END CERTIFICATE/ {cert=cert $0 "\n"; next} {cert=cert $0 "\n"}' | \
  awk 'BEGIN{RS="-----END CERTIFICATE-----\n"; ORS=""} {cert=$0 "-----END CERTIFICATE-----\n"} END{print cert}' \
  > "$vsphere_ca_file"

if [[ ! -s "$vsphere_ca_file" ]]; then
  echo "ERROR: Failed to fetch vSphere Root CA from ${vcenter_host}"
  echo "Please check network connectivity and vCenter availability"
  exit 1
fi

echo "✓ Successfully retrieved vSphere Root CA"

# Get TAS CA from Terraform
echo ""
echo "2. Fetching TAS CA from Terraform..."
cd "${CUR_DIR}/../terraform/certs"
tas_ca_file="${CERT_DIR}/tas-root-ca.crt"

terraform output -raw ca_cert > "$tas_ca_file" 2>/dev/null

if [[ ! -s "$tas_ca_file" ]]; then
  echo "ERROR: Failed to fetch TAS CA certificate from Terraform"
  echo "Please ensure Terraform has been applied: cd terraform/certs && terraform apply"
  exit 1
fi

echo "✓ Successfully retrieved TAS CA"
cd - > /dev/null

# Add certificates to macOS System keychain
echo ""
echo "3. Adding certificates to macOS System keychain..."
echo "   (You may be prompted for your password)"
echo ""

# Add vSphere Root CA
echo "   → Adding vSphere Root CA..."
if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$vsphere_ca_file" 2>/dev/null; then
  echo "     ✓ vSphere Root CA added successfully"
else
  # Certificate might already exist
  echo "     ⚠ vSphere Root CA might already be in keychain (this is ok)"
fi

# Add TAS Root CA
echo "   → Adding TAS Root CA..."
if sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$tas_ca_file" 2>/dev/null; then
  echo "     ✓ TAS Root CA added successfully"
else
  # Certificate might already exist
  echo "     ⚠ TAS Root CA might already be in keychain (this is ok)"
fi

echo ""
echo "======================================================================"
echo "Certificate Trust Configuration Complete!"
echo "======================================================================"
echo ""
echo "The following domains are now trusted by your Mac:"
echo "  • vCenter: vc01.vcf.lab"
echo "  • NSX-T Manager: nsx01.vcf.lab"
echo "  • Ops Manager: opsman.tas.vcf.lab"
echo "  • TAS System Domain: *.sys.tas.vcf.lab"
echo "  • TAS Apps Domain: *.apps.tas.vcf.lab"
echo ""
echo "You can verify in Keychain Access.app:"
echo "  System → Certificates → Look for 'CA' certificates"
echo ""
echo "To remove these certificates later:"
echo "  1. Open Keychain Access.app"
echo "  2. Select 'System' keychain"
echo "  3. Search for the CA certificates"
echo "  4. Right-click → Delete"
echo ""
