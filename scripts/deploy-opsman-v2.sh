#!/usr/bin/env bash
# ABOUTME: Deploy Ops Manager OVA to vSphere with proper configuration
# ABOUTME: Uses govc import.spec method and includes password for console access

set -euo pipefail

# Configuration
OPSMAN_OVA="${OPSMAN_OVA:-/tmp/ops-manager-vsphere-3.1.5.ova}"
OPSMAN_VM_NAME="ops-manager"
OPSMAN_IP="10.0.1.10"
OPSMAN_NETMASK="255.255.255.0"
OPSMAN_GATEWAY="10.0.1.1"
OPSMAN_DNS="192.168.10.2"
OPSMAN_NTP="pool.ntp.org"
OPSMAN_HOSTNAME="opsman.tas.vcf.lab"
NETWORK_NAME="tas-Infrastructure"
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

echo "=== Ops Manager Deployment Script v2 ==="
echo ""

# Check if VM already exists
if govc vm.info "$OPSMAN_VM_NAME" &>/dev/null; then
    echo "WARNING: VM '$OPSMAN_VM_NAME' already exists"
    read -p "Delete existing VM? (yes/no): " DELETE_VM
    if [[ "$DELETE_VM" == "yes" ]]; then
        echo "Powering off and deleting existing VM..."
        govc vm.power -off "$OPSMAN_VM_NAME" 2>/dev/null || true
        govc vm.destroy "$OPSMAN_VM_NAME" || true
        echo "Existing VM deleted"
    else
        echo "Aborting deployment"
        exit 1
    fi
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
govc import.spec "$OPSMAN_OVA" > /tmp/opsman-import-spec-v2.json

echo "=== Creating Import Configuration ==="
jq --arg ip "$OPSMAN_IP" \
   --arg netmask "$OPSMAN_NETMASK" \
   --arg gateway "$OPSMAN_GATEWAY" \
   --arg dns "$OPSMAN_DNS" \
   --arg ntp "$OPSMAN_NTP" \
   --arg hostname "$OPSMAN_HOSTNAME" \
   --arg ssh_key "$SSH_PUBLIC_KEY" \
   --arg network "$NETWORK_NAME" \
   '.DiskProvisioning = "thin" |
    .PowerOn = true |
    .Name = "'"$OPSMAN_VM_NAME"'" |
    .NetworkMapping[0].Network = $network |
    .PropertyMapping = [
      {Key: "ip0", Value: $ip},
      {Key: "netmask0", Value: $netmask},
      {Key: "gateway", Value: $gateway},
      {Key: "DNS", Value: $dns},
      {Key: "ntp_servers", Value: $ntp},
      {Key: "public_ssh_key", Value: $ssh_key},
      {Key: "custom_hostname", Value: $hostname}
    ]' /tmp/opsman-import-spec-v2.json > /tmp/opsman-import-final-v2.json

echo "=== Deploying Ops Manager OVA ==="
echo "This will take several minutes..."

govc import.ova \
  -folder="/$DATACENTER/vm/$VM_FOLDER" \
  -ds="$DATASTORE" \
  -pool="/$DATACENTER/host/VCF-Mgmt-Cluster/Resources/$RESOURCE_POOL" \
  -options=/tmp/opsman-import-final-v2.json \
  "$OPSMAN_OVA"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Ops Manager Details:"
echo "  VM Name: $OPSMAN_VM_NAME"
echo "  Internal IP: $OPSMAN_IP"
echo "  External IP: 31.31.10.10 (via NAT)"
echo "  Hostname: $OPSMAN_HOSTNAME"
echo "  SSH Key: $SSH_KEY_PATH"
echo ""
echo "Waiting for VM to boot and get IP address..."
echo "(This may take 2-3 minutes)"

# Wait for IP
for i in {1..30}; do
    VM_IP=$(govc vm.ip "$OPSMAN_VM_NAME" 2>/dev/null || echo "")
    if [[ -n "$VM_IP" ]]; then
        echo "VM has IP address: $VM_IP"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

echo ""
echo "=== Setting Console Password (for backup access) ==="
echo "Password will be: VMware1!"

# Wait for SSH to be available, then set password via SSH
echo "Waiting for SSH to become available..."
for i in {1..60}; do
    if timeout 3 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY_PATH" ubuntu@31.31.10.10 "echo 'SSH ready'" &>/dev/null; then
        echo "SSH is available! Setting console password..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" ubuntu@31.31.10.10 "echo 'ubuntu:VMware1!' | sudo chpasswd" 2>&1
        if [ $? -eq 0 ]; then
            echo "✓ Console password set successfully"
        else
            echo "⚠ Warning: Could not set console password (but SSH works)"
        fi
        break
    fi
    if [ $((i % 5)) -eq 0 ]; then
        echo "Still waiting for SSH... ($i/60)"
    fi
    sleep 2
done

echo ""
echo "Access Ops Manager:"
echo "  Web UI: https://31.31.10.10 or https://$OPSMAN_HOSTNAME"
echo "  SSH: ssh -i $SSH_KEY_PATH ubuntu@31.31.10.10"
echo "  Console: Username: ubuntu, Password: VMware1!"
echo ""
echo "NOTE: It may take 5-10 minutes for the web interface to become available"
echo "after the VM boots as services initialize."
