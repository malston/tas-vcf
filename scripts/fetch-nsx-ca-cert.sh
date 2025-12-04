#!/usr/bin/env bash
# ABOUTME: Fetches the NSX-T Manager CA certificate for BOSH Director configuration
# ABOUTME: Outputs the certificate in PEM format

set -euo pipefail

NSX_HOST="${NSX_HOST:-nsx01.vcf.lab}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/nsx-ca-cert.pem}"

echo "=== Fetching NSX-T Manager CA Certificate ==="
echo ""
echo "NSX Manager: $NSX_HOST"
echo "Output file: $OUTPUT_FILE"
echo ""

# Fetch the certificate using openssl
echo "Fetching certificate..."
echo | openssl s_client -connect "${NSX_HOST}:443" -showcerts 2>/dev/null | \
    openssl x509 -outform PEM > "$OUTPUT_FILE"

if [[ -s "$OUTPUT_FILE" ]]; then
    echo "✓ Certificate saved to: $OUTPUT_FILE"
    echo ""
    echo "Certificate details:"
    openssl x509 -in "$OUTPUT_FILE" -noout -subject -issuer -dates
    echo ""
    echo "To use in director.yml, copy the entire certificate including:"
    echo "  -----BEGIN CERTIFICATE-----"
    echo "  -----END CERTIFICATE-----"
    echo ""
    echo "Certificate content:"
    cat "$OUTPUT_FILE"
else
    echo "✗ Failed to fetch certificate"
    exit 1
fi
