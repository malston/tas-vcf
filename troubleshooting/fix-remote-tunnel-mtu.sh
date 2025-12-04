#!/bin/bash
# ABOUTME: Update remote tunnel physical MTU to match physical uplink MTU
# ABOUTME: Fixes MTU mismatch alarm by ensuring all MTU values are consistent

set -euo pipefail

NSX_MANAGER="nsx01.vcf.lab"
NSX_USER="admin"
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

echo "=== Updating Remote Tunnel Physical MTU to 9000 ==="

# Get current config
CURRENT_CONFIG=$(curl -k -s -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_MANAGER}/api/v1/global-configs/SwitchingGlobalConfig")

echo "Current configuration:"
echo "$CURRENT_CONFIG" | jq '{physical_uplink_mtu, remote_tunnel_physical_mtu, uplink_mtu_threshold}'

# Update remote_tunnel_physical_mtu to 9000
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq '.remote_tunnel_physical_mtu = 9000')

echo ""
echo "Applying update..."
curl -k -s -X PUT \
    -u "${NSX_USER}:${NSX_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_CONFIG" \
    "https://${NSX_MANAGER}/api/v1/global-configs/SwitchingGlobalConfig" | \
    jq '{physical_uplink_mtu, remote_tunnel_physical_mtu, uplink_mtu_threshold}'

echo ""
echo "✓ Remote tunnel physical MTU updated to 9000"
echo ""
echo "Waiting 30 seconds for NSX to re-evaluate..."
sleep 30

echo ""
echo "Checking alarms..."
curl -k -s -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_MANAGER}/api/v1/alarms?status=OPEN" | \
    jq -r '.results[]? | select(.feature_name == "mtu_check") |
        "[\(.severity)] \(.event_type) - Status: \(.status)"'

if [ $(curl -k -s -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_MANAGER}/api/v1/alarms?status=OPEN" | \
    jq -r '.results[]? | select(.feature_name == "mtu_check") | .id' | wc -l) -eq 0 ]; then
    echo "✓ SUCCESS: MTU alarm cleared!"
else
    echo "⚠ MTU alarm still present - may need manual resolution"
fi
