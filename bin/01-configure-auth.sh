#!/usr/bin/env bash
# ABOUTME: Configures Ops Manager authentication
# ABOUTME: Sets up internal authentication with username/password

set -e

CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION="vcf"

# Get Ops Manager credentials
opsman_username="admin"
opsman_password=$(op read "op://Private/opsman.tas.vcf.lab/password")
opsman_decryption_passphrase="$opsman_password"
opsman_hostname="opsman.tas.vcf.lab"

echo "===================================================================="
echo "Configuring Ops Manager Authentication"
echo "===================================================================="
echo ""
echo "Target: https://$opsman_hostname"
echo "Username: $opsman_username"
echo ""

# Check if Ops Manager is already configured
CONFIGURED=$(curl -k -s "https://$opsman_hostname/api/v0/info" | jq -r '.info.configured // false')

if [[ "$CONFIGURED" == "true" ]]; then
    echo "✅ Ops Manager is already configured"
    echo ""
    echo "Testing authentication..."

    # Test authentication
    ENV_FILE=$(mktemp)
    cat > "$ENV_FILE" <<EOF
target: $opsman_hostname
connect-timeout: 30
request-timeout: 1800
skip-ssl-validation: true
username: $opsman_username
password: $opsman_password
decryption-passphrase: $opsman_decryption_passphrase
EOF

    if om --env "$ENV_FILE" curl -path /api/v0/info >/dev/null 2>&1; then
        echo "✅ Authentication successful"
    else
        echo "❌ Authentication failed"
        echo "You may need to reconfigure authentication via the web UI"
    fi

    rm -f "$ENV_FILE"
    exit 0
fi

echo "Configuring internal authentication..."
echo ""

# Configure authentication
om -t "https://$opsman_hostname" -k \
  configure-authentication \
  --username "$opsman_username" \
  --password "$opsman_password" \
  --decryption-passphrase "$opsman_decryption_passphrase"

echo ""
echo "===================================================================="
echo "Authentication configured successfully!"
echo "===================================================================="
echo ""
echo "Credentials:"
echo "  URL: https://$opsman_hostname"
echo "  Username: $opsman_username"
echo "  Password: (stored in 1Password)"
echo ""
echo "Next steps:"
echo "  ./bin/02-configure-director.sh  # Configure BOSH Director"
echo ""
