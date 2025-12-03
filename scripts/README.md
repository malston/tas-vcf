# TAS on VCF Scripts

## Ops Manager Deployment

### deploy-opsman-v2.sh

Deploys Ops Manager OVA to vSphere with proper network configuration.

**Prerequisites:**

- OVA file at `/tmp/ops-manager-vsphere-3.1.5.ova`
- vCenter credentials in 1Password (`op://Private/vc01.vcf.lab/password`)
- NSX-T infrastructure already configured via Terraform

**Usage:**

```bash
cd /Users/markalston/workspace/tas-vcf
./scripts/deploy-opsman-v2.sh
```

**What it does:**

1. Checks for existing VM and offers to delete
2. Extracts proper OVA import specification
3. Configures network settings:
   - Internal IP: 10.0.1.10/24
   - Gateway: 10.0.1.1
   - DNS: 192.168.10.2
   - External IP: 31.31.10.10 (via NAT)
4. Sets up SSH key: `~/.ssh/vcf_opsman_ssh_key`
5. Deploys VM to:
   - Resource Pool: tas-infrastructure
   - Network: tas-Infrastructure segment
   - Datastore: vsanDatastore
6. Powers on and waits for boot

**Expected time:** 5-10 minutes

**Access after deployment:**

- Web UI: <https://31.31.10.10> or <https://opsman.tas.vcf.lab>
- SSH: `ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.10.10`

**Note:** It may take an additional 5-10 minutes after VM boot for all services (nginx, ssh) to start and be accessible.

## Troubleshooting

### Check VM Status

```bash
export GOVC_URL="vc01.vcf.lab"
export GOVC_USERNAME="administrator@vsphere.local"
export GOVC_INSECURE="true"
export GOVC_DATACENTER="VCF-Datacenter"
export GOVC_PASSWORD=$(op read "op://Private/vc01.vcf.lab/password")

govc vm.info ops-manager
```

### Test Network Connectivity

```bash
# ICMP (should work)
ping -c 2 31.31.10.10

# HTTPS (may take time to start)
curl -k https://31.31.10.10

# SSH
ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.10.10
```

### Check from ESXi Host

```bash
ssh esx01
ping -c 2 10.0.1.10
nc -zv 10.0.1.10 443
```

## Network Infrastructure

See `CLAUDE.md` for complete network topology documentation.

**Key IPs:**

- Ops Manager Internal: 10.0.1.10
- Ops Manager External: 31.31.10.10
- Infrastructure Gateway: 10.0.1.1
- T0 Uplinks: 172.30.70.2-3 (VLAN 70)

**Verified Working:**

- ✅ T0 uplinks operational
- ✅ T1 gateways configured
- ✅ NAT rules functional
- ✅ DNS resolution working
- ✅ All NSX-T firewalls disabled
