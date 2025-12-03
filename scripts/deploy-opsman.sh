#!/bin/bash
# ABOUTME: Deploys Ops Manager OVA to vSphere using govc.
# ABOUTME: Uses 1Password CLI to retrieve vCenter credentials securely.

set -euo pipefail

# vCenter connection
export GOVC_URL="${GOVC_URL:-vc01.vcf.lab}"
export GOVC_USERNAME="${GOVC_USERNAME:-administrator@vsphere.local}"
export GOVC_INSECURE="${GOVC_INSECURE:-true}"

# vSphere targets
DATACENTER="VCF-Datacenter"
CLUSTER="VCF-Mgmt-Cluster"
DATASTORE="vsanDatastore"
RESOURCE_POOL="tas-infrastructure"
NETWORK="tas-Infrastructure"
VM_FOLDER="tas/vms"
VM_NAME="ops-manager"

# Ops Manager network config
OPSMAN_IP="10.0.1.10"
OPSMAN_NETMASK="255.255.255.0"
OPSMAN_GATEWAY="10.0.1.1"
OPSMAN_DNS="192.168.10.2"
OPSMAN_NTP="pool.ntp.org"
OPSMAN_HOSTNAME="opsman.tas.vcf.lab"

# OVA source
HTTP_USER="vcf"
HTTP_PASS=$(op read "op://Private/VCF Offline Depot/password")
OVA_URL="http://carbonite.markalston.net:8889/Foundation%20Core%203.1.5/ops-manager-vsphere-3.1.5.ova"
LOCAL_OVA="/tmp/ops-manager-vsphere-3.1.5.ova"

echo "=== Ops Manager Deployment ==="
echo ""

# Get vCenter password from 1Password
echo "Fetching vCenter credentials from 1Password..."
export GOVC_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

if [[ -z "$GOVC_PASSWORD" ]]; then
    echo "ERROR: Failed to retrieve password from 1Password"
    exit 1
fi

# Set datacenter context
export GOVC_DATACENTER="$DATACENTER"

# Verify connection
echo "Verifying vCenter connection..."
if ! govc about > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to vCenter at $GOVC_URL"
    exit 1
fi
echo "  Connected to $(govc about | grep Name | awk '{print $2, $3}')"

# Check if VM already exists
VM_EXISTS=$(govc find . -type m -name "$VM_NAME" 2>/dev/null)
if [[ -n "$VM_EXISTS" ]]; then
    echo ""
    echo "WARNING: VM '$VM_NAME' already exists at: $VM_EXISTS"
    echo "To redeploy, first delete with: govc vm.destroy $VM_NAME"
    exit 1
fi

# Verify target resources exist
echo ""
echo "Verifying target resources..."
govc ls "/$DATACENTER/host/$CLUSTER/Resources/$RESOURCE_POOL" > /dev/null || {
    echo "ERROR: Resource pool '$RESOURCE_POOL' not found"
    exit 1
}
echo "  Resource pool: $RESOURCE_POOL ✓"

govc ls "/$DATACENTER/datastore/$DATASTORE" > /dev/null || {
    echo "ERROR: Datastore '$DATASTORE' not found"
    exit 1
}
echo "  Datastore: $DATASTORE ✓"

# Check network exists (NSX-T segment)
if ! govc ls "/$DATACENTER/network/$NETWORK" > /dev/null 2>&1; then
    echo "WARNING: Network '$NETWORK' not found in inventory"
    echo "  NSX-T segments may take time to appear. Continuing anyway..."
fi
echo "  Network: $NETWORK"

# Ensure VM folder exists
echo ""
echo "Ensuring VM folder exists..."
govc folder.create "/$DATACENTER/vm/$VM_FOLDER" 2>/dev/null || true
echo "  Folder: $VM_FOLDER ✓"

# Download OVA if not already present
echo ""
if [[ -f "$LOCAL_OVA" ]]; then
    echo "OVA already downloaded: $LOCAL_OVA"
    echo "  Size: $(ls -lh "$LOCAL_OVA" | awk '{print $5}')"
else
    echo "Downloading Ops Manager OVA..."
    echo "  Source: $OVA_URL"
    echo "  Destination: $LOCAL_OVA"
    echo "  This may take several minutes (7GB)..."
    curl -u "${HTTP_USER}:${HTTP_PASS}" -o "$LOCAL_OVA" "$OVA_URL"
    echo "  Download complete!"
fi

# Deploy OVA
echo ""
echo "Deploying Ops Manager OVA to vSphere..."
echo "  This may take several minutes..."
echo ""

# Create options file for OVA import
OPTIONS_FILE=$(mktemp)
trap "rm -f $OPTIONS_FILE" EXIT

# Read SSH public key
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$(cat ~/.ssh/vcf_opsman_ssh_key.pub)}"

cat > "$OPTIONS_FILE" <<EOF
{
  "NetworkMapping": [
    {
      "Name": "Network 1",
      "Network": "$NETWORK"
    }
  ],
  "PropertyMapping": [
    {"Key": "ip0", "Value": "$OPSMAN_IP"},
    {"Key": "netmask0", "Value": "$OPSMAN_NETMASK"},
    {"Key": "gateway", "Value": "$OPSMAN_GATEWAY"},
    {"Key": "DNS", "Value": "$OPSMAN_DNS"},
    {"Key": "ntp_servers", "Value": "$OPSMAN_NTP"},
    {"Key": "custom_hostname", "Value": "$OPSMAN_HOSTNAME"},
    {"Key": "public_ssh_key", "Value": "$SSH_PUBLIC_KEY"}
  ],
  "DiskProvisioning": "thin"
}
EOF

govc import.ova \
    -name="$VM_NAME" \
    -folder="/$DATACENTER/vm/$VM_FOLDER" \
    -ds="$DATASTORE" \
    -pool="/$DATACENTER/host/$CLUSTER/Resources/$RESOURCE_POOL" \
    -options="$OPTIONS_FILE" \
    "$LOCAL_OVA"

echo ""
echo "OVA deployed successfully!"

# Power on the VM
echo ""
echo "Powering on Ops Manager VM..."
govc vm.power -on "$VM_NAME"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Ops Manager is starting up. It may take 5-10 minutes to become available."
echo ""
echo "Next steps:"
echo "  1. Wait for Ops Manager to boot: curl -k https://$OPSMAN_HOSTNAME"
echo "  2. Set up authentication at: https://$OPSMAN_HOSTNAME/setup"
echo "  3. Configure BOSH Director using om CLI"
echo ""
echo "Monitor VM status:"
echo "  govc vm.info $VM_NAME"
echo ""
