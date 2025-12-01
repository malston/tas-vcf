#!/bin/bash
# ABOUTME: Queries vCenter API to discover object names for Terraform configuration.
# ABOUTME: Uses 1Password CLI to retrieve credentials securely.

set -euo pipefail

VCENTER_HOST="${VCENTER_HOST:-vc01.vcf.lab}"
VCENTER_USER="${VCENTER_USER:-administrator@vsphere.local}"

echo "Fetching vCenter credentials from 1Password..."
VCENTER_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

if [[ -z "$VCENTER_PASSWORD" ]]; then
    echo "ERROR: Failed to retrieve password from 1Password"
    echo "Looking for: op://Private/vc01.vcf.lab/password or op://Private/vcenter/password"
    exit 1
fi

echo "Authenticating to vCenter at ${VCENTER_HOST}..."

# Get session token
SESSION_TOKEN=$(curl -sk -X POST \
    "https://${VCENTER_HOST}/api/session" \
    -u "${VCENTER_USER}:${VCENTER_PASSWORD}" | tr -d '"')

if [[ -z "$SESSION_TOKEN" || "$SESSION_TOKEN" == "null" ]]; then
    echo "ERROR: Failed to authenticate to vCenter"
    exit 1
fi

echo "Querying vCenter API..."
echo ""

# Datacenters
echo "=== Datacenters ==="
curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/datacenter" | \
    jq -r '.[] | "  \(.name) (id: \(.datacenter))"'
echo ""

# Clusters
echo "=== Clusters ==="
curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/cluster" | \
    jq -r '.[] | "  \(.name) (id: \(.cluster))"'
echo ""

# Datastores
echo "=== Datastores ==="
curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/datastore" | \
    jq -r '.[] | "  \(.name) (type: \(.type), capacity: \(.capacity // "unknown"))"'
echo ""

# Hosts
echo "=== Hosts ==="
curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/host" | \
    jq -r '.[] | "  \(.name) (state: \(.connection_state))"'
echo ""

# Resource Pools (existing)
echo "=== Resource Pools ==="
curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/resource-pool" | \
    jq -r '.[] | "  \(.name)"'
echo ""

# Logout
curl -sk -X DELETE \
    "https://${VCENTER_HOST}/api/session" \
    -H "vmware-api-session-id: ${SESSION_TOKEN}" > /dev/null 2>&1

echo "=== Suggested tfvars values ==="
# Re-authenticate for final queries
SESSION_TOKEN=$(curl -sk -X POST \
    "https://${VCENTER_HOST}/api/session" \
    -u "${VCENTER_USER}:${VCENTER_PASSWORD}" | tr -d '"')

DATACENTER=$(curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/datacenter" | jq -r '.[0].name')
CLUSTER=$(curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/cluster" | jq -r '.[0].name')
DATASTORE=$(curl -sk -H "vmware-api-session-id: ${SESSION_TOKEN}" \
    "https://${VCENTER_HOST}/api/vcenter/datastore" | jq -r '.[] | select(.type=="VSAN") | .name' | head -1)

curl -sk -X DELETE \
    "https://${VCENTER_HOST}/api/session" \
    -H "vmware-api-session-id: ${SESSION_TOKEN}" > /dev/null 2>&1

echo "datacenter_name = \"${DATACENTER}\""
echo "cluster_name    = \"${CLUSTER}\""
echo "datastore_name  = \"${DATASTORE}\""
