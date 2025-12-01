#!/bin/bash
# ABOUTME: Queries NSX-T API to discover object names for Terraform configuration.
# ABOUTME: Uses 1Password CLI to retrieve credentials securely.

set -euo pipefail

NSX_HOST="${NSX_HOST:-nsx01.vcf.lab}"
NSX_USER="${NSX_USER:-admin}"

echo "Fetching NSX-T credentials from 1Password..."
NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/j_password")

if [[ -z "$NSX_PASSWORD" ]]; then
    echo "ERROR: Failed to retrieve password from 1Password"
    exit 1
fi

echo "Querying NSX-T API at ${NSX_HOST}..."
echo ""

# Edge Clusters
echo "=== Edge Clusters ==="
curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/api/v1/edge-clusters" | \
    jq -r '.results[] | "  \(.display_name) (id: \(.id))"'
echo ""

# Overlay Transport Zones
echo "=== Overlay Transport Zones ==="
curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/api/v1/transport-zones" | \
    jq -r '.results[] | select(.transport_type=="OVERLAY") | "  \(.display_name) (id: \(.id))"'
echo ""

# T0 Gateways (Policy API)
echo "=== Tier-0 Gateways ==="
curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/policy/api/v1/infra/tier-0s" | \
    jq -r '.results[] | "  \(.display_name) (path: \(.path))"'
echo ""

# Existing T1 Gateways (to avoid conflicts)
echo "=== Existing Tier-1 Gateways ==="
curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/policy/api/v1/infra/tier-1s" | \
    jq -r '.results[] | "  \(.display_name)"' 2>/dev/null || echo "  (none)"
echo ""

echo "=== Suggested tfvars values ==="
EDGE_CLUSTER=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/api/v1/edge-clusters" | jq -r '.results[0].display_name')

T0_GATEWAY=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/policy/api/v1/infra/tier-0s" | jq -r '.results[0].display_name')

# Get transport zone from T0's edge cluster binding to ensure compatibility
T0_PATH=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/policy/api/v1/infra/tier-0s" | jq -r '.results[0].path')
T0_LOCALE=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
    "https://${NSX_HOST}/policy/api/v1${T0_PATH}/locale-services" | jq -r '.results[0].id // empty')

if [[ -n "$T0_LOCALE" ]]; then
    # Get edge cluster from T0's locale service, then find its transport zone
    EDGE_CLUSTER_PATH=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
        "https://${NSX_HOST}/policy/api/v1${T0_PATH}/locale-services/${T0_LOCALE}" | \
        jq -r '.edge_cluster_path // empty')
    if [[ -n "$EDGE_CLUSTER_PATH" ]]; then
        # Get the transport zone name that matches the VCF/T0 setup
        # Prefer vcf-overlay-TZ if it exists, otherwise use first overlay TZ
        TRANSPORT_ZONE=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
            "https://${NSX_HOST}/api/v1/transport-zones" | \
            jq -r '.results[] | select(.transport_type=="OVERLAY") | .display_name' | \
            grep -i "vcf" | head -1)
    fi
fi

# Fallback if we couldn't determine the right TZ
if [[ -z "$TRANSPORT_ZONE" ]]; then
    TRANSPORT_ZONE=$(curl -sk -u "${NSX_USER}:${NSX_PASSWORD}" \
        "https://${NSX_HOST}/api/v1/transport-zones" | \
        jq -r '.results[] | select(.transport_type=="OVERLAY") | .display_name' | head -1)
    echo "# WARNING: Multiple overlay transport zones found. Verify this is correct:"
fi

echo "edge_cluster_name   = \"${EDGE_CLUSTER}\""
echo "transport_zone_name = \"${TRANSPORT_ZONE}\""
echo "t0_gateway_name     = \"${T0_GATEWAY}\""
