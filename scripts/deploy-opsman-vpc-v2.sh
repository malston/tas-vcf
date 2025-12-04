#!/usr/bin/env bash
# ABOUTME: Deploy Ops Manager OVA to NSX VPC tas-infrastructure subnet with full vApp config
# ABOUTME: Sets static IP on VPC subnet, external IP assigned manually via NSX UI

set -euo pipefail

# Logging configuration
LOG_FILE="${LOG_FILE:-/tmp/opsman-vpc-deploy.log}"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==================================================================="
echo "Deployment started at $(date)"
echo "Log file: $LOG_FILE"
echo "==================================================================="

# Configuration
OPSMAN_OVA="${OPSMAN_OVA:-/tmp/ops-manager-vsphere-3.1.5.ova}"
OPSMAN_VM_NAME="ops-manager"
OPSMAN_HOSTNAME="opsman.tas.vcf.lab"
NETWORK_NAME="tas-infrastructure"  # VPC subnet name
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/vcf_opsman_ssh_key}"

# VPC Subnet Network Configuration
OPSMAN_IP="172.20.0.10"
NETMASK="255.255.255.0"
GATEWAY="172.20.0.1"
DNS="192.168.10.2"
NTP="pool.ntp.org"

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

echo "=== Ops Manager VPC Deployment Script v2 ==="
echo ""
echo "Deploying to VPC subnet: $NETWORK_NAME"
echo "VPC: tas-vpc (172.20.0.0/16)"
echo "Subnet CIDR: 172.20.0.0/24"
echo "Internal IP: $OPSMAN_IP"
echo ""

# Check if VM already exists and delete
if govc find / -type m -name "$OPSMAN_VM_NAME" 2>/dev/null | grep -q .; then
    echo "Deleting existing VM..."
    govc vm.power -off -force "$OPSMAN_VM_NAME" 2>/dev/null || true
    govc vm.destroy "$OPSMAN_VM_NAME" || true
    sleep 2
fi

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
govc import.spec "$OPSMAN_OVA" > /tmp/opsman-import-spec-vpc2.json

echo "=== Creating Import Configuration ==="
jq --arg ssh_key "$SSH_PUBLIC_KEY" \
   --arg network "$NETWORK_NAME" \
   --arg vmname "$OPSMAN_VM_NAME" \
   --arg ip "$OPSMAN_IP" \
   --arg netmask "$NETMASK" \
   --arg gateway "$GATEWAY" \
   --arg dns "$DNS" \
   --arg ntp "$NTP" \
   --arg custom_hostname "$OPSMAN_HOSTNAME" \
   '.DiskProvisioning = "thin" |
    .PowerOn = false |
    .Name = $vmname |
    .NetworkMapping[0].Network = $network |
    .PropertyMapping = [
      {Key: "ip0", Value: $ip},
      {Key: "netmask0", Value: $netmask},
      {Key: "gateway", Value: $gateway},
      {Key: "DNS", Value: $dns},
      {Key: "ntp_servers", Value: $ntp},
      {Key: "public_ssh_key", Value: $ssh_key},
      {Key: "custom_hostname", Value: $custom_hostname}
    ]' /tmp/opsman-import-spec-vpc2.json > /tmp/opsman-import-final-vpc2.json

echo "=== Deploying Ops Manager OVA ==="
echo "This will take several minutes (typically 5-10 minutes depending on network speed)..."
echo "Started at: $(date)"
echo ""

# Run govc import in foreground so we can see all output
govc import.ova \
  -folder="/$DATACENTER/vm/$VM_FOLDER" \
  -ds="$DATASTORE" \
  -pool="/$DATACENTER/host/VCF-Mgmt-Cluster/Resources/$RESOURCE_POOL" \
  -options=/tmp/opsman-import-final-vpc2.json \
  "$OPSMAN_OVA"

echo ""
echo "OVA import completed at: $(date)"

echo ""
echo "=== Powering on VM ==="
govc vm.power -on "$OPSMAN_VM_NAME"

echo ""
echo "=== Waiting for VM to boot and configure network ==="
echo "VM should get internal IP: $OPSMAN_IP"

# Wait for VM to get IP
for i in {1..60}; do
    VM_IP=$(govc vm.info -json "$OPSMAN_VM_NAME" | jq -r '.VirtualMachines[0].Guest.IpAddress // empty')
    if [[ -n "$VM_IP" && "$VM_IP" != "null" ]]; then
        echo "✓ VM has IP address: $VM_IP"
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
echo "✓ Internal IP: $VM_IP"
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
