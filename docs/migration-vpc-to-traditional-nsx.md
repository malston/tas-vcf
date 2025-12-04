# Migration Plan: VPC to Traditional NSX-T

## Overview

This document provides step-by-step instructions to migrate from NSX VPC (`tas-infrastructure` VPC subnet) to traditional NSX-T segments (`tas-Infrastructure`). The migration addresses BOSH CPI incompatibility with VPC segment port APIs.

**Duration**: ~1 hour
**Downtime**: Yes (Ops Manager redeployment required)
**Risk**: Low (network infrastructure already exists)

## Prerequisites Verification

Before starting, verify these resources exist:

```bash
# 1. Check traditional NSX-T segments exist
govc ls /VCF-Datacenter/network | grep tas-

# Expected output:
# /VCF-Datacenter/network/tas-Infrastructure
# /VCF-Datacenter/network/tas-Deployment
# /VCF-Datacenter/network/tas-Services

# 2. Verify NAT rules exist
export NSX_MANAGER="nsx01.vcf.lab"
export NSX_USERNAME="admin"
export NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

curl -k -s -u "$NSX_USERNAME:$NSX_PASSWORD" \
  "https://$NSX_MANAGER/policy/api/v1/infra/tier-0s/transit-gw/nat/USER/nat-rules" | \
  jq -r '.results[] | select(.display_name | contains("tas-")) | {name: .display_name, action, source: .source_network, translated: .translated_network}'

# Expected: 3 NAT rules (SNAT-All, SNAT-OpsManager, DNAT-OpsManager)

# 3. Check Terraform state
cd /Users/markalston/workspace/tas-vcf/terraform/nsxt
terraform state list | grep -E "(segment|nat_rule)"
```

**✅ All checks passed**: Proceed with migration
**❌ Missing resources**: Run `terraform apply` first

---

## Phase 1: Backup Current State (5 minutes)

### 1.1 Export Ops Manager Configuration

```bash
# SSH to Ops Manager
ssh ubuntu@opsman.tas.vcf.lab

# Export installation
om export-installation --output-file /tmp/installation-backup-$(date +%Y%m%d).zip

# Exit and download backup
exit
scp ubuntu@opsman.tas.vcf.lab:/tmp/installation-backup-*.zip ~/backups/
```

### 1.2 Document Current State

```bash
# Save current network info
govc vm.info ops-manager > /tmp/opsman-vpc-state.txt

# Save current IP
echo "Current Ops Manager IP: $(govc vm.info ops-manager | grep 'IP address')" >> /tmp/opsman-vpc-state.txt
```

---

## Phase 2: Deploy New Ops Manager on Traditional Segment (15 minutes)

### 2.1 Power Off and Remove Current Ops Manager

```bash
# Power off current Ops Manager (on VPC)
govc vm.power -off ops-manager

# Optional: Rename for safety instead of deleting
govc vm.markasvm ops-manager
govc object.mv /VCF-Datacenter/vm/tas/vms/ops-manager /VCF-Datacenter/vm/ops-manager-vpc-backup

# OR delete if confident
# govc vm.destroy ops-manager
```

### 2.2 Prepare Deployment Spec for Traditional Segment

```bash
# Extract OVA spec
govc import.spec ~/Downloads/ops-manager-vsphere-3.1.5.ova > /tmp/opsman-nsx-t.json

# Edit the spec with correct network
cat > /tmp/opsman-nsx-t.json <<'EOF'
{
  "DiskProvisioning": "thin",
  "IPAllocationPolicy": "fixedPolicy",
  "IPProtocol": "IPv4",
  "PropertyMapping": [
    {
      "Key": "ip0",
      "Value": "10.0.1.10"
    },
    {
      "Key": "netmask0",
      "Value": "255.255.255.0"
    },
    {
      "Key": "gateway",
      "Value": "10.0.1.1"
    },
    {
      "Key": "DNS",
      "Value": "192.168.10.2"
    },
    {
      "Key": "ntp_servers",
      "Value": "pool.ntp.org"
    },
    {
      "Key": "admin_password",
      "Value": ""
    },
    {
      "Key": "custom_hostname",
      "Value": "opsman.tas.vcf.lab"
    },
    {
      "Key": "public_ssh_key",
      "Value": "$(cat ~/.ssh/vcf_opsman_ssh_key.pub)"
    }
  ],
  "NetworkMapping": [
    {
      "Name": "Network 1",
      "Network": "tas-Infrastructure"
    }
  ],
  "MarkAsTemplate": false,
  "PowerOn": false,
  "InjectOvfEnv": false,
  "WaitForIP": false,
  "Name": "ops-manager"
}
EOF
```

### 2.3 Deploy Ops Manager on Traditional Segment

```bash
# Deploy OVA with correct network
govc import.ova \
  -dc=VCF-Datacenter \
  -pool=/VCF-Datacenter/host/VCF-Mgmt-Cluster/Resources/tas-infrastructure \
  -ds=vsanDatastore \
  -folder=tas/vms \
  -name=ops-manager \
  -options=/tmp/opsman-nsx-t.json \
  ~/Downloads/ops-manager-vsphere-3.1.5.ova

# Power on
govc vm.power -on ops-manager

# Wait for boot (2-3 minutes)
echo "Waiting for Ops Manager to boot..."
sleep 180
```

### 2.4 Verify Network Connectivity

```bash
# Check VM has correct IP
govc vm.info ops-manager | grep "IP address"
# Expected: IP address:   10.0.1.10

# Check VM network
govc vm.info -r ops-manager | grep "Network:"
# Expected: Network:              tas-Infrastructure

# Test ICMP via NAT
ping -c 3 31.31.10.10
# Should succeed

# Test SSH via NAT (may take 5 minutes for SSH to start)
for i in {1..30}; do
  if ssh -i ~/.ssh/vcf_opsman_ssh_key -o ConnectTimeout=2 ubuntu@31.31.10.10 'echo "SSH works"' 2>/dev/null; then
    echo "✅ SSH connectivity confirmed"
    break
  fi
  echo "Waiting for SSH ($i/30)..."
  sleep 10
done
```

**⚠️ If SSH times out after 5 minutes**: Check NAT rules are active (see Troubleshooting section)

---

## Phase 3: Update Director Configuration (5 minutes)

### 3.1 Update vars/director.yml

```bash
cd /Users/markalston/workspace/tas-vcf

# Update network configuration
cat > foundations/vcf/vars/director.yml <<'EOF'
---
# vCenter
vcenter_host: vc01.vcf.lab
vcenter_username: ((vcenter_username))
vcenter_password: ((vcenter_password))
datacenter_name: VCF-Datacenter
cluster_name: VCF-Mgmt-Cluster
datastore_name: vsanDatastore

# Ops Manager
ops_manager_hostname: opsman.tas.vcf.lab

# Resource pools
az1_resource_pool: tas-az1
az2_resource_pool: tas-az2

# Folders
vm_folder: tas_vms
template_folder: tas_templates
disk_folder: tas_disks

# NSX-T
nsxt_host: nsx01.vcf.lab
nsxt_username: ((nsxt_username))
nsxt_password: ((nsxt_password))
# vSphere Root CA cert (signs NSX-T Manager certificate)
nsxt_ca_cert: |
  -----BEGIN CERTIFICATE-----
  MIIE8DCCA1igAwIBAgIJAO0HwBb0WuDzMA0GCSqGSIb3DQEBCwUAMIGTMQswCQYD
  VQQDDAJDQTEXMBUGCgmSJomT8ixkARkWB3ZzcGhlcmUxFTATBgoJkiaJk/IsZAEZ
  FgVsb2NhbDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNV
  BAoMDHZjMDEudmNmLmxhYjEbMBkGA1UECwwSVk13YXJlIEVuZ2luZWVyaW5nMB4X
  DTI1MTEwOTIyMTIzN1oXDTM1MTEwNzIyMTIzN1owgZMxCzAJBgNVBAMMAkNBMRcw
  FQYKCZImiZPyLGQBGRYHdnNwaGVyZTEVMBMGCgmSJomT8ixkARkWBWxvY2FsMQsw
  CQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEVMBMGA1UECgwMdmMwMS52
  Y2YubGFiMRswGQYDVQQLDBJWTXdhcmUgRW5naW5lZXJpbmcwggGiMA0GCSqGSIb3
  DQEBAQUAA4IBjwAwggGKAoIBgQC18ooG02hUjpzawf5TcDM5QJH+dhbSdvC3iFiK
  dx43LY3atZCJmwxB7H7MQtPpGlD16UB03eXocIAX07VQULC+gKY7kzutjkqgrtN2
  UURqN/cSCpfv1IhYvDJd8HHW+uZl2oiCJigSd390V516SYQvyOX75vPnlV1PYrEM
  BP/UzfZ4oVU98DX0T+le/NWngvZntZNqyTfZZ8nmZySSjdN7D0UMD7y4kHVFrBoA
  mrYh4UPiNNJwaubr8tslhBwS++SJXQLSWPFC/0LtfEoZtpwTnf+lkb/XhWnDOnQs
  WfBERZ58WI3XxiHDNIgBAC5SYKbQnAu5U8NdGCp0lhIoXjhbm7ZO7QED+1U349ZP
  RU9lVp5Y//aHnkr8HbNcc4ZIpDM4K5/4ugI6zZ9+1xYZv3xNnLG5h1BH9N4ECKrC
  mQsyVE+moVBVbV/6Hgf8oaOmqeQdTw09/bNNHuJgB/NXa70u5fVhB9n1M79i7Mbl
  biJgLHe8Oid3zKOrYyf9Xfg8eTcCAwEAAaNFMEMwHQYDVR0OBBYEFH+kaZJ0wInR
  1Ug6sMPaSAGcz+9rMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEA
  MA0GCSqGSIb3DQEBCwUAA4IBgQCITS7dTnU6FtwXfgs5xXcKiIcGf8RftrHqJSOI
  XrXxWuxgJnLmq5C3m+ePm1f5yzktmNxBj9IVfpcKbpFZ+2ieopyfwYYt19RFI5Ly
  u2p4+IlJxA9l18h+yB071vLGBf3spfcw4BFQJbTfLfovxe0vt3aU7Im0ubwJ9sUu
  W+V7A7ijjEBKmdmmwPZkZRw3HpTZd/3tS37X3idNkA3z4nQWTgatSjapxKquW9sF
  Uw6IyrOIPQWEZJHJ7i0U7TiJW3PWiHx+ihuONoIREuDqW/IppM22aQ6JcOjjXks8
  MKDD+/soC6oKICz+T86NidAX5DlPghSQiXkalRuayt/7h9FO/mSWz7LrHfq9rRz/
  NAurSgbT5Ou1D20jUIu3cUJVfu5eLwuG7rWF0BdZI6XHhRmtJdAiy1k9rws8L4+N
  2u1B1ezlcbZSuOlqSa7AeMeqYiyZGD0MTFeNyE7g5pBUfQCOtPChQm7TduHdEgR5
  HkwFLJgLRarHjVRIgPina/2Qcsk=
  -----END CERTIFICATE-----

# Networks - Traditional NSX-T Infrastructure Segment
# CRITICAL: Must use exact segment name (case-sensitive)
infrastructure_network_name: tas-Infrastructure
infrastructure_cidr: 10.0.1.0/24
infrastructure_gateway: 10.0.1.1
infrastructure_reserved_ips: 10.0.1.1-10.0.1.9

# DNS and NTP
dns_servers: 192.168.10.2
ntp_servers: pool.ntp.org

# Certificates - NSX CA cert trusted by all BOSH VMs
trusted_certificates: |
  -----BEGIN CERTIFICATE-----
  MIIE8DCCA1igAwIBAgIJAO0HwBb0WuDzMA0GCSqGSIb3DQEBCwUAMIGTMQswCQYD
  VQQDDAJDQTEXMBUGCgmSJomT8ixkARkWB3ZzcGhlcmUxFTATBgoJkiaJk/IsZAEZ
  FgVsb2NhbDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFTATBgNV
  BAoMDHZjMDEudmNmLmxhYjEbMBkGA1UECwwSVk13YXJlIEVuZ2luZWVyaW5nMB4X
  DTI1MTEwOTIyMTIzN1oXDTM1MTEwNzIyMTIzN1owgZMxCzAJBgNVBAMMAkNBMRcw
  FQYKCZImiZPyLGQBGRYHdnNwaGVyZTEVMBMGCgmSJomT8ixkARkWBWxvY2FsMQsw
  CQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEVMBMGA1UECgwMdmMwMS52
  Y2YubGFiMRswGQYDVQQLDBJWTXdhcmUgRW5naW5lZXJpbmcwggGiMA0GCSqGSIb3
  DQEBAQUAA4IBjwAwggGKAoIBgQC18ooG02hUjpzawf5TcDM5QJH+dhbSdvC3iFiK
  dx43LY3atZCJmwxB7H7MQtPpGlD16UB03eXocIAX07VQULC+gKY7kzutjkqgrtN2
  UURqN/cSCpfv1IhYvDJd8HHW+uZl2oiCJigSd390V516SYQvyOX75vPnlV1PYrEM
  BP/UzfZ4oVU98DX0T+le/NWngvZntZNqyTfZZ8nmZySSjdN7D0UMD7y4kHVFrBoA
  mrYh4UPiNNJwaubr8tslhBwS++SJXQLSWPFC/0LtfEoZtpwTnf+lkb/XhWnDOnQs
  WfBERZ58WI3XxiHDNIgBAC5SYKbQnAu5U8NdGCp0lhIoXjhbm7ZO7QED+1U349ZP
  RU9lVp5Y//aHnkr8HbNcc4ZIpDM4K5/4ugI6zZ9+1xYZv3xNnLG5h1BH9N4ECKrC
  mQsyVE+moVBVbV/6Hgf8oaOmqeQdTw09/bNNHuJgB/NXa70u5fVhB9n1M79i7Mbl
  biJgLHe8Oid3zKOrYyf9Xfg8eTcCAwEAAaNFMEMwHQYDVR0OBBYEFH+kaZJ0wInR
  1Ug6sMPaSAGcz+9rMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAGAQH/AgEA
  MA0GCSqGSIb3DQEBCwUAA4IBgQCITS7dTnU6FtwXfgs5xXcKiIcGf8RftrHqJSOI
  XrXxWuxgJnLmq5C3m+ePm1f5yzktmNxBj9IVfpcKbpFZ+2ieopyfwYYt19RFI5Ly
  u2p4+IlJxA9l18h+yB071vLGBf3spfcw4BFQJbTfLfovxe0vt3aU7Im0ubwJ9sUu
  W+V7A7ijjEBKmdmmwPZkZRw3HpTZd/3tS37X3idNkA3z4nQWTgatSjapxKquW9sF
  Uw6IyrOIPQWEZJHJ7i0U7TiJW3PWiHx+ihuONoIREuDqW/IppM22aQ6JcOjjXks8
  MKDD+/soC6oKICz+T86NidAX5DlPghSQiXkalRuayt/7h9FO/mSWz7LrHfq9rRz/
  NAurSgbT5Ou1D20jUIu3cUJVfu5eLwuG7rWF0BdZI6XHhRmtJdAiy1k9rws8L4+N
  2u1B1ezlcbZSuOlqSa7AeMeqYiyZGD0MTFeNyE7g5pBUfQCOtPChQm7TduHdEgR5
  HkwFLJgLRarHjVRIgPina/2Qcsk=
  -----END CERTIFICATE-----
EOF
```

### 3.2 Verify Configuration Changes

```bash
# Check the key changes
grep -A 5 "infrastructure_network_name" foundations/vcf/vars/director.yml

# Expected output:
# infrastructure_network_name: tas-Infrastructure  (capital I)
# infrastructure_cidr: 10.0.1.0/24  (10.0.x.x, not 172.20.x.x)
# infrastructure_gateway: 10.0.1.1
```

---

## Phase 4: Configure and Deploy BOSH Director (30 minutes)

### 4.1 Configure Ops Manager Authentication

```bash
./bin/01-configure-auth.sh
```

**Expected output**: Authentication configured successfully

### 4.2 Configure BOSH Director

```bash
./bin/02-configure-director.sh
```

**Verify output shows**:

- Network: `tas-Infrastructure` (capital I)
- CIDR: `10.0.1.0/24`
- Gateway: `10.0.1.1`
- NSX mode: `nsx-t`

### 4.3 Deploy BOSH Director

```bash
# Deploy with logging
./bin/03-apply-director-changes.sh 2>&1 | tee /tmp/director-deploy-$(date +%Y%m%d-%H%M%S).log
```

**Expected deployment steps**:

1. ✅ Pre-deploy check passes
2. ✅ Validating releases (~20 seconds)
3. ✅ Installing CPI (~10 seconds)
4. ✅ Uploading stemcell (~1 minute or skipped)
5. ✅ Creating VM for instance 'bosh/0' (~2 minutes)
6. ✅ Setting VM metadata (should NOT fail now)
7. ✅ Waiting for agent (~1 minute)
8. ✅ Updating instance settings (~5 minutes)
9. ✅ Compiling packages (~10 minutes)
10. ✅ Updating jobs (~5 minutes)

**Total time**: 20-30 minutes

### 4.4 Verify BOSH Director Deployment

```bash
# Check BOSH VM exists
govc ls /VCF-Datacenter/vm/tas_vms | grep bosh

# Expected: /VCF-Datacenter/vm/tas_vms/vm-<uuid>

# Check BOSH VM has IP in correct range
govc find . -type m -name "vm-*" | grep tas_vms | head -1 | xargs govc vm.info | grep "IP address"

# Expected: IP address:   10.0.1.x (in range 10.0.1.20-10.0.1.254)

# SSH to Ops Manager and test BOSH
ssh ubuntu@opsman.tas.vcf.lab

# Authenticate with BOSH
bosh alias-env bosh -e 10.0.1.x --ca-cert /var/tempest/workspaces/default/root_ca_certificate
export BOSH_CLIENT=ops_manager
export BOSH_CLIENT_SECRET=$(bosh int /var/tempest/workspaces/default/deployments/vars.yml --path /admin_password)
export BOSH_ENVIRONMENT=bosh

# Verify BOSH works
bosh -e bosh env
bosh -e bosh vms

# Expected: Shows bosh/0 VM running
exit
```

---

## Phase 5: Post-Migration Verification (10 minutes)

### 5.1 Network Connectivity Tests

```bash
# From your laptop

# 1. ICMP to external IP
ping -c 3 31.31.10.10
# ✅ Should succeed

# 2. SSH to Ops Manager
ssh ubuntu@opsman.tas.vcf.lab 'hostname'
# ✅ Should return hostname

# 3. HTTPS to Ops Manager UI
curl -k https://opsman.tas.vcf.lab
# ✅ Should return HTML

# 4. Access Ops Manager web UI
open https://opsman.tas.vcf.lab
# ✅ Should load login page
```

### 5.2 NSX-T Integration Verification

```bash
# Check BOSH VM has NSX tags
export NSX_MANAGER="nsx01.vcf.lab"
export NSX_USERNAME="admin"
export NSX_PASSWORD=$(op read "op://Private/nsx01.vcf.lab/password")

# Get BOSH VM ID from vCenter
BOSH_VM_ID=$(govc find . -type m -name "vm-*" | grep tas_vms | head -1 | xargs govc vm.info -json | jq -r '.virtualMachines[0].config.instanceUuid')

# Check VM has NSX segment port
curl -k -s -u "$NSX_USERNAME:$NSX_PASSWORD" \
  "https://$NSX_MANAGER/api/v1/fabric/virtual-machines?external_id=$BOSH_VM_ID" | \
  jq -r '.results[0] | {display_name, external_id}'

# ✅ Should return VM info with external_id matching
```

### 5.3 Document Final State

```bash
# Save final network configuration
cat > /tmp/migration-complete.txt <<EOF
Migration Complete: $(date)

Network: Traditional NSX-T Segments
Ops Manager:
  - Internal IP: 10.0.1.10
  - External IP: 31.31.10.10 (via DNAT)
  - Network: tas-Infrastructure
  - URL: https://opsman.tas.vcf.lab

BOSH Director:
  - Status: Deployed
  - Network: tas-Infrastructure (10.0.1.0/24)
  - NSX Integration: Enabled (nsx-t mode)

NAT Rules:
  - SNAT: 10.0.0.0/16 → 31.31.10.1
  - DNAT: 31.31.10.10 → 10.0.1.10
  - SNAT: 10.0.1.10 → 31.31.10.10

Next Steps:
  - Upload stemcells
  - Upload TAS tile
  - Configure TAS
  - Deploy TAS
EOF

cat /tmp/migration-complete.txt
```

---

## Troubleshooting

### Issue: SSH to new Ops Manager times out

**Symptoms**: `ping 31.31.10.10` works but `ssh ubuntu@31.31.10.10` times out

**Diagnosis**:

```bash
# Check NAT rules are active
curl -k -s -u "$NSX_USERNAME:$NSX_PASSWORD" \
  "https://$NSX_MANAGER/policy/api/v1/infra/tier-0s/transit-gw/nat/USER/nat-rules" | \
  jq -r '.results[] | select(.display_name | contains("OpsManager"))'
```

**Fix**:

```bash
# If NAT rules missing, reapply Terraform
cd /Users/markalston/workspace/tas-vcf/terraform/nsxt
terraform apply
```

### Issue: BOSH Director deployment fails with segment port error

**Symptoms**: Same error as before: "segment port not found"

**Diagnosis**: Director config still has VPC settings

**Fix**:

```bash
# Verify director vars
grep infrastructure_network_name foundations/vcf/vars/director.yml

# Should show: tas-Infrastructure (capital I)
# If lowercase, re-run Phase 3.1
```

### Issue: VM created but no IP assigned

**Symptoms**: BOSH VM exists but has no IP

**Diagnosis**: VM on wrong network or DHCP not working

**Fix**:

```bash
# Check VM network
BOSH_VM=$(govc find . -type m -name "vm-*" | grep tas_vms | head -1)
govc vm.info -r "$BOSH_VM" | grep "Network:"

# Should show: tas-Infrastructure
# If wrong, check director config and redeploy
```

### Issue: Can't access Ops Manager web UI

**Symptoms**: SSH works but HTTPS times out

**Diagnosis**: Ops Manager services not started

**Fix**:

```bash
# SSH to Ops Manager
ssh ubuntu@opsman.tas.vcf.lab

# Check services
sudo systemctl status tempest-web
sudo systemctl status nginx

# Restart if needed
sudo systemctl restart tempest-web
sudo systemctl restart nginx
```

---

## Rollback Procedure (If Migration Fails)

If migration fails and you need to return to VPC:

```bash
# 1. Power off new Ops Manager
govc vm.power -off ops-manager
govc vm.destroy ops-manager

# 2. Restore VPC Ops Manager (if renamed, not deleted)
govc object.mv /VCF-Datacenter/vm/ops-manager-vpc-backup /VCF-Datacenter/vm/tas/vms/ops-manager
govc vm.power -on ops-manager

# 3. Wait for boot
sleep 180

# 4. Verify connectivity
ping -c 3 31.31.0.11
ssh ubuntu@opsman.tas.vcf.lab
```

---

## Key Differences Reference

| Aspect | VPC (Before) | Traditional NSX-T (After) |
|--------|--------------|---------------------------|
| **Network Name** | `tas-infrastructure` (lowercase) | `tas-Infrastructure` (capital I) |
| **CIDR** | 172.20.0.0/24 | 10.0.1.0/24 |
| **Gateway** | 172.20.0.1 | 10.0.1.1 |
| **Ops Manager Internal** | 172.20.0.10 | 10.0.1.10 |
| **Ops Manager External** | 31.31.0.11 (VPC auto) | 31.31.10.10 (DNAT) |
| **NSX Integration** | Not compatible | ✅ Full support |
| **BOSH CPI** | ❌ Fails on segment ports | ✅ Works correctly |
| **Reserved IPs** | 172.20.0.1-172.20.0.10 | 10.0.1.1-10.0.1.9 |

---

## Success Criteria

Migration is successful when:

- ✅ Ops Manager accessible at <https://opsman.tas.vcf.lab> (31.31.10.10)
- ✅ Ops Manager VM has internal IP 10.0.1.10
- ✅ Ops Manager VM connected to `tas-Infrastructure` segment
- ✅ BOSH Director deployed successfully
- ✅ BOSH VM exists in tas_vms folder with 10.0.1.x IP
- ✅ BOSH CPI can set VM metadata (no segment port errors)
- ✅ NSX tags visible on BOSH VM in NSX Manager

---

## Next Steps After Migration

1. **Upload Stemcells**:

   ```bash
   om upload-stemcell --stemcell ubuntu-jammy-1.xxx-vsphere.tgz
   ```

2. **Upload TAS Tile**:

   ```bash
   om upload-product --product srt-x.x.x-build.xxx.pivotal
   ```

3. **Stage TAS**:

   ```bash
   om stage-product --product-name cf --product-version x.x.x
   ```

4. **Configure TAS**: Use Ops Manager UI or `om configure-product`

5. **Deploy TAS**:

   ```bash
   om apply-changes
   ```

---

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Project context (needs updating post-migration)
- [network-topology.md](network-topology.md) - VPC topology (reference only)
- [Terraform NSX-T Module](../terraform/nsxt/) - Infrastructure definitions
- [Director Configuration Guide](director-configuration-guide.md) - Manual config reference

---

**Migration Author**: Claude
**Last Updated**: 2025-12-04
**Status**: Ready for execution
