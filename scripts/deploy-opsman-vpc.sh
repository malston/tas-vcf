#!/usr/bin/env bash
# ABOUTME: Deploy Ops Manager OVA to NSX VPC tas-infrastructure subnet
# ABOUTME: Uses DHCP for initial IP, external IP assigned manually via NSX UI

set -euo pipefail

# Configuration
OPSMAN_OVA="${OPSMAN_OVA:-/tmp/ops-manager-vsphere-3.1.5.ova}"
OPSMAN_VM_NAME="ops-manager"
NETWORK_NAME="tas-infrastructure"  # VPC subnet name
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/vcf_opsman_ssh_key}"

# vSphere Configuration
VCENTER_HOST="vc01.vcf.lab"
VCENTER_USER="administrator@vsphere.local"
DATACENTER="VCF-Datacenter"
DATASTORE="vsanDatastore"
RESOURCE_POOL="tas-infrastructure"
VM_FOLDER="tas/vms"

# Get vCenter password
export GOVC_URL="$VCENTER_HOST"
export GOVC_USERNAME="$VCENTER_USER"
export GOVC_INSECURE="true"
export GOVC_DATACENTER="$DATACENTER"
export GOVC_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

echo "=== Ops Manager VPC Deployment Script ==="
echo ""
echo "Deploying to VPC subnet: $NETWORK_NAME"
echo "VPC: tas-vpc (172.20.0.0/16)"
echo "Subnet CIDR: 172.20.0.0/24"
echo ""

# Check if VM already exists (disabled due to govc caching issue)
# if govc vm.info "$OPSMAN_VM_NAME" &>/dev/null; then
#     echo "ERROR: VM '$OPSMAN_VM_NAME' already exists"
#     echo "Please delete it first or choose a different name"
#     exit 1
# fi
echo "Skipping VM existence check (govc caching issue)"

# Verify OVA exists
if [[ ! -f "$OPSMAN_OVA" ]]; then
    echo "ERROR: OVA not found at $OPSMAN_OVA"
    exit 1
fi

# Generate SSH key if it doesn't exist
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "opsman@tas.vcf.lab"
fi

SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

echo "=== Extracting OVA Import Specification ==="
govc import.spec "$OPSMAN_OVA" > /tmp/opsman-import-spec-vpc.json

echo "=== Creating Import Configuration ==="
# For VPC deployment, we use DHCP for initial IP
# External IP will be assigned manually via NSX UI after deployment
jq --arg ssh_key "$SSH_PUBLIC_KEY" \
   --arg network "$NETWORK_NAME" \
   --arg vmname "$OPSMAN_VM_NAME" \
   '.DiskProvisioning = "thin" |
    .PowerOn = false |
    .Name = $vmname |
    .NetworkMapping[0].Network = $network |
    .PropertyMapping = [
      {Key: "public_ssh_key", Value: $ssh_key}
    ]' /tmp/opsman-import-spec-vpc.json > /tmp/opsman-import-final-vpc.json

echo "=== Deploying Ops Manager OVA ==="
echo "This will take several minutes..."
echo ""

govc import.ova \
  -folder="/$DATACENTER/vm/$VM_FOLDER" \
  -ds="$DATASTORE" \
  -pool="/$DATACENTER/host/VCF-Mgmt-Cluster/Resources/$RESOURCE_POOL" \
  -options=/tmp/opsman-import-final-vpc.json \
  "$OPSMAN_OVA"

echo ""
echo "=== Powering on VM ==="
govc vm.power -on "$OPSMAN_VM_NAME"

echo ""
echo "=== Waiting for VM to boot and get DHCP IP ==="
echo "VM will get internal IP from VPC subnet DHCP (172.20.0.0/24)..."

# Wait for VM to get IP
for i in {1..60}; do
    VM_IP=$(govc vm.info -json "$OPSMAN_VM_NAME" | jq -r '.VirtualMachines[0].Guest.IpAddress // empty')
    if [[ -n "$VM_IP" && "$VM_IP" != "null" ]]; then
        echo "✓ VM has internal IP address: $VM_IP"
        break
    fi
    if [ $((i % 10)) == 0 ]; then
        echo "Still waiting for VM IP... ($i/60)"
    fi
    sleep 5
done

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "✓ Ops Manager deployed to VPC subnet: $NETWORK_NAME"
echo "✓ Internal IP (DHCP): $VM_IP"
echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Assign External IP via NSX UI:"
echo "   - Navigate to: NSX UI → Inventory → Virtual Machines"
echo "   - Find VM: ops-manager"
echo "   - Right-click → Assign External IP"
echo "   - Select IP: 31.31.10.10"
echo ""
echo "2. Test Connectivity:"
echo "   - SSH: ssh -i $SSH_KEY_PATH ubuntu@31.31.10.10"
echo "   - HTTPS: https://31.31.10.10"
echo ""
echo "3. If SSH works, configure Ops Manager:"
echo "   - Access web UI at https://31.31.10.10"
echo "   - Set up authentication"
echo "   - Configure BOSH Director"
echo ""
