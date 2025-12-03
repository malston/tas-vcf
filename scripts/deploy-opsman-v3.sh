#!/usr/bin/env bash
# ABOUTME: Deploy Ops Manager OVA with cloud-init workaround for console password
# ABOUTME: Creates ISO with cloud-init data to set password on first boot

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
CONSOLE_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

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

echo "=== Ops Manager Deployment Script v3 (with cloud-init workaround) ==="
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

echo "=== Creating cloud-init userdata ISO ==="

# Create cloud-init userdata
cat > /tmp/opsman-user-data <<EOF
#cloud-config
users:
  - name: ubuntu
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: \$(openssl passwd -6 '$CONSOLE_PASSWORD')
    ssh_authorized_keys:
      - $SSH_PUBLIC_KEY

# Ensure SSH is enabled and started
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
  - systemctl status ssh
  - ufw disable || true
  - echo "Cloud-init complete at \$(date)" >> /var/log/cloud-init-custom.log

write_files:
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          ens192:
            addresses:
              - $OPSMAN_IP/24
            gateway4: $OPSMAN_GATEWAY
            nameservers:
              addresses:
                - $OPSMAN_DNS

power_state:
  mode: reboot
  condition: True
EOF

# Create empty meta-data
cat > /tmp/opsman-meta-data <<EOF
instance-id: ops-manager-001
local-hostname: $OPSMAN_HOSTNAME
EOF

# Create ISO from cloud-init files
echo "Creating cloud-init ISO..."
if command -v genisoimage &>/dev/null; then
    genisoimage -output /tmp/opsman-cloud-init.iso \
      -volid cidata -joliet -rock \
      /tmp/opsman-user-data /tmp/opsman-meta-data
elif command -v mkisofs &>/dev/null; then
    mkisofs -output /tmp/opsman-cloud-init.iso \
      -volid cidata -joliet -rock \
      /tmp/opsman-user-data /tmp/opsman-meta-data
elif command -v hdiutil &>/dev/null; then
    # macOS approach
    mkdir -p /tmp/opsman-cidata
    cp /tmp/opsman-user-data /tmp/opsman-cidata/user-data
    cp /tmp/opsman-meta-data /tmp/opsman-cidata/meta-data
    hdiutil makehybrid -o /tmp/opsman-cloud-init.iso /tmp/opsman-cidata -iso -joliet
    rm -rf /tmp/opsman-cidata
else
    echo "ERROR: No ISO creation tool found (genisoimage, mkisofs, or hdiutil required)"
    exit 1
fi

echo "=== Extracting OVA Import Specification ==="
govc import.spec "$OPSMAN_OVA" > /tmp/opsman-import-spec-v3.json

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
    .PowerOn = false |
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
    ]' /tmp/opsman-import-spec-v3.json > /tmp/opsman-import-final-v3.json

echo "=== Deploying Ops Manager OVA ==="
echo "This will take several minutes..."
govc import.ova \
  -folder="/$DATACENTER/vm/$VM_FOLDER" \
  -ds="$DATASTORE" \
  -pool="/$DATACENTER/host/VCF-Mgmt-Cluster/Resources/$RESOURCE_POOL" \
  -options=/tmp/opsman-import-final-v3.json \
  "$OPSMAN_OVA"

echo ""
echo "=== Uploading cloud-init ISO to datastore ==="
govc datastore.upload -ds "$DATASTORE" /tmp/opsman-cloud-init.iso "$OPSMAN_VM_NAME/cloud-init.iso"

echo "=== Attaching cloud-init ISO to VM ==="
govc device.cdrom.add -vm "$OPSMAN_VM_NAME"
govc device.cdrom.insert -vm "$OPSMAN_VM_NAME" -device cdrom-3000 "[$DATASTORE] $OPSMAN_VM_NAME/cloud-init.iso"

echo ""
echo "=== Powering on VM ==="
govc vm.power -on "$OPSMAN_VM_NAME"

echo ""
echo "=== Waiting for VM to boot and cloud-init to complete ==="
echo "This may take 3-5 minutes for cloud-init to configure the system..."

# Wait for VM to get IP
for i in {1..60}; do
    if govc vm.info "$OPSMAN_VM_NAME" | grep -q "IP address:.*$OPSMAN_IP"; then
        echo "✓ VM has IP address: $OPSMAN_IP"
        break
    fi
    if [ $((i % 10)) == 0 ]; then
        echo "Still waiting for VM IP... ($i/60)"
    fi
    sleep 5
done

# Wait for cloud-init to complete (it reboots the VM)
echo "Waiting for cloud-init to complete (VM will reboot)..."
sleep 60

# Wait for SSH after cloud-init reboot
echo ""
echo "=== Waiting for SSH to become available after cloud-init ==="
for i in {1..60}; do
    if timeout 3 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY_PATH" ubuntu@31.31.10.10 "echo 'SSH ready'" &>/dev/null; then
        echo "✓ SSH is available!"

        # Verify cloud-init completed
        echo "Checking cloud-init status..."
        ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" ubuntu@31.31.10.10 "cloud-init status --wait" || true

        break
    fi
    if [ $((i % 5)) == 0 ]; then
        echo "Still waiting for SSH... ($i/60)"
    fi
    sleep 2
done

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Access Ops Manager:"
echo "  Web UI: https://31.31.10.10 or https://$OPSMAN_HOSTNAME"
echo "  SSH: ssh -i $SSH_KEY_PATH ubuntu@31.31.10.10"
echo "  Console: Username: ubuntu, Password: $CONSOLE_PASSWORD"
echo ""
echo "If SSH still doesn't work, you can access via console with the password above."
echo "Then diagnose with:"
echo "  sudo systemctl status ssh"
echo "  sudo ufw status"
echo "  sudo ss -tlnp | grep :22"
echo ""
