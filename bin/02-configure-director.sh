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

# vSphere Root CA (signs NSX-T Manager certificate)
vsphere_ca="-----BEGIN CERTIFICATE-----
MIIE8DCCA1igAwIBAgIJAO0HwBb0WuDzMA0GCSqGSIb3DQEBCwUAMIGTMQswCQYD
VQQDDAJDQTEXMBUGCgmSJomT8ixkARkWB3ZzcGhlcmUxFTATBgoJkiaJk/IsZAEZ
FgVsb2NhbDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNV
BAoMDHZjMDEudmNmLmxhYjEbMBkGA1UECwwSVk13YXJlIEVuZ2luZWVyaW5nMB4X
DTI1MTEwOTIyMTIzN1oXDTM1MTEwNzIyMTIzN1owgZMxCzAJBgNVBAMMAkNBMRcw
FQYKCZImiZPyLGQBGRYHdnNwaGVyZTEVMBMGCgmSJomT8ixkARkWBWxvY2FsMQsw
CQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEVMBMGA1UECgwMdmMwMS52
Y2YubGFiMRswGQYDVQQLDBJWTXdhcmUgRW5naW5lZXJpbmcwggGiMA0GCSqGSIb3
DQEBAQUAA4IBjwAwggGKAoIBgQC18ooG02hUjpzawf5TcDM5QJH+dhbSdvC3iFiK
dx43LY3atZCJmwxB7H7MQtPpGlD16UB03eXocIAX07VQULC+gKY7kzutjkqgrtN2
UURqN/cSCpfv1IhYvDJd8HHW+uZl2oiCJigSd390V516SYQvyOX75vPnlV1PYrEM
BP/UzfZ4oVU98DX0T+le/NWngvZntZNqyTfZZ8nmZySSjdN7D0UMD7y4kHVFrBoA
mrYh4UPiNNJwaubr8tslhBwS++SJXQLSWPFC/0LtfEoZtpwTnf+lkb/XhWnDOnQs
WfBERZ58WI3XxiHDNIgBAC5SYKbQnAu5U8NdGCp0lhIoXjhbm7ZO7QED+1U349ZP
RU9lVp5Y//aHnkr8HbNcc4ZIpDM4K5/4ugI6zZ9+1xYZv3xNnLG5h1BH9N4ECKrC
mQsyVE+moVBVbV/6Hgf8oaOmqeQdTw09/bNNHuJgB/NXa70u5fVhB9n1M79i7Mbl
biJgLHe8Oid3zKOrYyf9Xfg8eTcCAwEAAaNFMEMwHQYDVR0OBBYEFH+kaZJ0wInR
1Ug6sMPaSAGcz+9rMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEA
MA0GCSqGSIb3DQEBCwUAA4IBgQCITS7dTnU6FtwXfgs5xXcKiIcGf8RftrHqJSOI
XrXxWuxgJnLmq5C3m+ePm1f5yzktmNxBj9IVfpcKbpFZ+2ieopyfwYYt19RFI5Ly
u2p4+IlJxA9l18h+yB071vLGBf3spfcw4BFQJbTfLfovxe0vt3aU7Im0ubwJ9sUu
W+V7A7ijjEBKmdmmwPZkZRw3HpTZd/3tS37X3idNkA3z4nQWTgatSjapxKquW9sF
Uw6IyrOIPQWEZJHJ7i0U7TiJW3PWiHx+ihuONoIREuDqW/IppM22aQ6JcOjjXks8
MKDD+/soC6oKICz+T86NidAX5DlPghSQiXkalRuayt/7h9FO/mSWz7LrHfq9rRz/
NAurSgbT5Ou1D20jUIu3cUJVfu5eLwuG7rWF0BdZI6XHhRmtJdAiy1k9rws8L4+N
2u1B1ezlcbZSuOlqSa7AeMeqYiyZGD0MTFeNyE7g5pBUfQCOtPChQm7TduHdEgR5
HkwFLJgLRarHjVRIgPina/2Qcsk=
-----END CERTIFICATE-----"

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
