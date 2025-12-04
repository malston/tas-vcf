#!/bin/bash
# ABOUTME: Comprehensive MTU diagnosis and fix script for NSX
# ABOUTME: Identifies MTU mismatches and applies consistent configuration

set -euo pipefail

NSX_MANAGER="nsx01.vcf.lab"
NSX_USER="admin"
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

echo "=========================================="
echo "NSX MTU Configuration Diagnosis"
echo "=========================================="
echo ""

# Function to make NSX API calls
nsx_api() {
    local endpoint="$1"
    curl -k -s -u "${NSX_USER}:${NSX_PASSWORD}" \
        "https://${NSX_MANAGER}${endpoint}"
}

echo "=== 1. Global Switching Configuration ==="
echo "Checking physical uplink MTU (global default)..."
GLOBAL_MTU=$(nsx_api "/api/v1/global-configs/SwitchingGlobalConfig" | \
    jq -r '.physical_uplink_mtu // "not configured"')
echo "Global Physical Uplink MTU: ${GLOBAL_MTU}"
echo ""

echo "=== 2. Host Switch Profiles ==="
echo "Checking uplink profiles for MTU settings..."
nsx_api "/api/v1/host-switch-profiles" | \
    jq -r '.results[]? | select(.resource_type == "UplinkHostSwitchProfile") |
        "Profile: \(.display_name)\n  ID: \(.id)\n  MTU: \(.mtu // "not configured")\n  Transport VLAN: \(.transport_vlan // "not configured")\n"'
echo ""

echo "=== 3. Transport Zones ==="
echo "Listing all transport zones..."
nsx_api "/api/v1/transport-zones" | \
    jq -r '.results[]? |
        "TZ: \(.display_name) (\(.transport_type))\n  ID: \(.id)\n"'
echo ""

echo "=== 4. Transport Nodes ==="
echo ""
echo "ESXi Hosts:"
nsx_api "/api/v1/transport-nodes" | \
    jq -r '.results[]? | select(.node_deployment_info.resource_type == "HostNode") |
        "  - \(.display_name) (\(.node_deployment_info.ip_addresses[0] // "no IP"))\n"'

echo "Edge Nodes:"
nsx_api "/api/v1/transport-nodes" | \
    jq -r '.results[]? | select(.node_deployment_info.resource_type == "EdgeNode") |
        "  - \(.display_name) (\(.node_deployment_info.ip_addresses[0] // "no IP"))\n"'
echo ""

echo "=== 5. Active MTU Alarms ==="
echo "Checking for MTU-related alarms..."
nsx_api "/api/v1/alarms" | \
    jq -r '.results[]? | select(.status == "OPEN" and .feature_name == "MTU Check") |
        "[\(.severity)] \(.event_type)\n  Entity: \(.entity_display_name)\n  Description: \(.description)\n  First Reported: \(.first_event_timestamp)\n"'
echo ""

echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="
echo ""
echo "NEXT STEPS:"
echo "1. Review the MTU values above"
echo "2. Identify which nodes have mismatched MTU"
echo "3. Choose target MTU:"
echo "   - Option A: 1700 bytes (minimum recommended)"
echo "   - Option B: 9000 bytes (jumbo frames, if physical infrastructure supports)"
echo ""
echo "To apply the fix, run:"
echo "  ./fix-mtu-mismatch.sh [1700|9000]"
