#!/bin/bash
# ABOUTME: Apply consistent MTU configuration across NSX transport infrastructure
# ABOUTME: Usage: ./fix-mtu-mismatch.sh [1700|9000]

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 [1700|9000]"
    echo "  1700 - Minimum recommended MTU for NSX overlay"
    echo "  9000 - Jumbo frames (requires physical infrastructure support)"
    exit 1
fi

TARGET_MTU="$1"

if [[ ! "$TARGET_MTU" =~ ^(1700|9000)$ ]]; then
    echo "ERROR: MTU must be 1700 or 9000"
    exit 1
fi

NSX_MANAGER="nsx01.vcf.lab"
NSX_USER="admin"
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

echo "=========================================="
echo "NSX MTU Fix - Setting MTU to ${TARGET_MTU}"
echo "=========================================="
echo ""

# Function to make NSX API calls
nsx_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [ -z "$data" ]; then
        curl -k -s -X "$method" \
            -u "${NSX_USER}:${NSX_PASSWORD}" \
            "https://${NSX_MANAGER}${endpoint}"
    else
        curl -k -s -X "$method" \
            -u "${NSX_USER}:${NSX_PASSWORD}" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "https://${NSX_MANAGER}${endpoint}"
    fi
}

echo "Step 1: Update Global Switching Configuration"
echo "Setting physical_uplink_mtu to ${TARGET_MTU}..."

# Get current config
CURRENT_CONFIG=$(nsx_api GET "/api/v1/global-configs/SwitchingGlobalConfig")
REVISION=$(echo "$CURRENT_CONFIG" | jq -r '._revision')

# Update with new MTU
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq ".physical_uplink_mtu = ${TARGET_MTU}")

nsx_api PUT "/api/v1/global-configs/SwitchingGlobalConfig" "$UPDATED_CONFIG"
echo "✓ Global MTU updated to ${TARGET_MTU}"
echo ""

echo "Step 2: Update Host Switch Profiles"
echo "Finding and updating uplink profiles..."

# Get all uplink profiles
PROFILES=$(nsx_api GET "/api/v1/host-switch-profiles" | \
    jq -r '.results[]? | select(.resource_type == "UplinkHostSwitchProfile") | .id')

if [ -z "$PROFILES" ]; then
    echo "⚠ No UplinkHostSwitchProfiles found (may be VCF-managed)"
else
    for PROFILE_ID in $PROFILES; do
        echo "  Updating profile: $PROFILE_ID"

        # Get current profile
        PROFILE_CONFIG=$(nsx_api GET "/api/v1/host-switch-profiles/${PROFILE_ID}")

        # Update MTU
        UPDATED_PROFILE=$(echo "$PROFILE_CONFIG" | jq ".mtu = ${TARGET_MTU}")

        nsx_api PUT "/api/v1/host-switch-profiles/${PROFILE_ID}" "$UPDATED_PROFILE"
        echo "  ✓ Profile ${PROFILE_ID} updated"
    done
fi
echo ""

echo "Step 3: Verification"
echo "Waiting 30 seconds for changes to propagate..."
sleep 30

echo ""
echo "Checking for remaining MTU alarms..."
REMAINING_ALARMS=$(nsx_api GET "/api/v1/alarms" | \
    jq -r '.results[]? | select(.status == "OPEN" and .feature_name == "MTU Check") | .id' | wc -l)

if [ "$REMAINING_ALARMS" -eq 0 ]; then
    echo "✓ SUCCESS: No MTU alarms remaining"
else
    echo "⚠ WARNING: ${REMAINING_ALARMS} MTU alarm(s) still active"
    echo "  The alarm may take a few minutes to clear"
    echo "  Run this script again in 5 minutes to check"
fi

echo ""
echo "=========================================="
echo "MTU Fix Complete"
echo "=========================================="
echo ""
echo "IMPORTANT NOTES:"
if [ "$TARGET_MTU" == "9000" ]; then
    echo "- Physical switches must support MTU 9000"
    echo "- vSphere VDS must have MTU 9000 configured"
    echo "- Guest VMs should use MTU 8800 (accounting for Geneve overhead)"
else
    echo "- MTU ${TARGET_MTU} is the minimum recommended"
    echo "- Consider upgrading to 9000 if infrastructure supports it"
fi
echo ""
echo "To verify the fix, run:"
echo "  ./diagnose-and-fix-mtu.sh"
