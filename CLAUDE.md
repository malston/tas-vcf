# TAS on VCF 9 - Project Context

## Network Infrastructure (VERIFIED WORKING)

### T0 Gateway Configuration
- **T0 Gateway**: `transit-gw` (existing from VCF deployment)
- **Edge Cluster**: `ec-01`
- **HA Mode**: Active/Standby
- **Uplinks** (on VLAN 70):
  - Edge 01: 172.30.70.2/24
  - Edge 02: 172.30.70.3/24
  - Connects to VLAN segments: `vlan-segment-teaming-1-*`
- **Static Route**: 0.0.0.0/0 → 172.30.70.1
- **Status**: ✅ Fully functional (ICMP reachability confirmed)

### T1 Gateways
All T1 gateways created by Terraform, connected to T0 `transit-gw`:

| T1 Gateway | ID | Purpose | Firewall Status |
|------------|-----|---------|----------------|
| tas-T1-Infrastructure | 3b62aea5-8dab-4eda-9ff3-62cd0249b4f6 | Ops Manager, BOSH | ✅ Disabled |
| tas-T1-Deployment | 2ca988eb-ca08-40cd-a59d-223b3c663b41 | TAS VMs | ✅ Disabled |
| tas-T1-Services | fcda2709-1219-492f-88a9-93ca8fa18e3c | Services | ✅ Disabled |

**CRITICAL FIX**: T1 firewalls were initially enabled with NO rules (default DENY), blocking all TCP traffic. Fixed by setting `enable_firewall = false` in `terraform/nsxt/t1_gateways.tf`.

### NSX-T Segments
| Segment | CIDR | Gateway | T1 Router |
|---------|------|---------|-----------|
| tas-Infrastructure | 10.0.1.0/24 | 10.0.1.1 | tas-T1-Infrastructure |
| tas-Deployment | 10.0.2.0/24 | 10.0.2.1 | tas-T1-Deployment |
| tas-Services | 10.0.3.0/24 | 10.0.3.1 | tas-T1-Services |

### NAT Configuration
All NAT rules on T0 gateway `transit-gw`:

| Rule | Type | External IP | Internal IP | Status |
|------|------|-------------|-------------|--------|
| tas-SNAT-All | SNAT | 31.31.10.1 | 10.0.0.0/16 | ✅ Active |
| tas-SNAT-OpsManager | SNAT | 31.31.10.10 | 10.0.1.10 | ✅ Active |
| tas-DNAT-OpsManager | DNAT | 31.31.10.10 | 10.0.1.10 | ✅ Active |

**NAT Verification**: ICMP to 31.31.10.10 works (proves NAT is functional).

### External IP Allocation
- **NAT Gateway**: 31.31.10.1
- **Ops Manager**: 31.31.10.10
- **Web LB VIP**: 31.31.10.20 (HTTP/HTTPS)
- **SSH LB VIP**: 31.31.10.21 (Diego SSH)
- **TCP LB VIP**: 31.31.10.22 (TCP Router)
- **IP Pool**: 31.31.10.100-200 (Container networking)

## Ops Manager Deployment

### Current Status
- **VM Name**: ops-manager
- **Power State**: Powered On
- **Internal IP**: 10.0.1.10 (via vApp properties)
- **External IP**: 31.31.10.10 (via DNAT)
- **Host**: esx01.vcf.lab
- **Resource Pool**: tas-infrastructure
- **Network**: tas-Infrastructure segment
- **Boot Time**: 2025-12-03 16:55:02 UTC

### Deployment Method
- **OVA**: ops-manager-vsphere-3.1.5.ova
- **Deployment Tool**: govc import.ova
- **Configuration**:
  - Used `govc import.spec` to extract proper vApp property schema
  - Static IP configured via vApp properties
  - SSH key configured: `~/.ssh/vcf_opsman_ssh_key.key`
  - NO password set (SSH key only)

### Network Connectivity Status
- ✅ **ICMP**: Ping to 31.31.10.10 succeeds (~190ms latency)
- ❌ **TCP (Port 22)**: SSH connection times out
- ❌ **TCP (Port 443)**: HTTPS connection times out
- ✅ **DNS**: opsman.tas.vcf.lab → 31.31.10.10
- ✅ **Console**: VM accessible via vSphere console

### Known Issue: TCP Connectivity
**Problem**: ICMP works but TCP (SSH/HTTPS) times out despite:
- ✅ NAT rules functional (ICMP proves this)
- ✅ T1 firewalls disabled
- ✅ VM powered on with correct IP
- ✅ No T0 firewall blocking

**Root Cause**: VM internal firewall or services not listening on ports 22/443.

**Next Steps**:
1. Access VM via vSphere console
2. Check internal firewall: `sudo ufw status`
3. Check listening ports: `sudo ss -tlnp | grep -E ':(22|443)'`
4. Check service status: `systemctl status ssh nginx`
5. Set password via GRUB if needed for console access

## Terraform State

### Applied Configuration
- **NSX-T Module**: `terraform/nsxt/`
  - 3 T1 gateways ✅
  - 3 segments ✅
  - 3 NAT rules ✅
  - Load balancer components ✅
  - IP pools/blocks ✅
  - **Firewall fix applied**: `enable_firewall = false`

### Terraform Outputs
```
infrastructure_segment_name = "tas-Infrastructure"
ops_manager_external_ip = "31.31.10.10"
t1_infrastructure_path = "/infra/tier-1s/3b62aea5-8dab-4eda-9ff3-62cd0249b4f6"
web_lb_vip = "31.31.10.20"
```

## Lessons Learned

### T1 Gateway Firewalls
**Issue**: Enabling T1 firewalls without defining rules creates default DENY-ALL policy.
**Symptom**: ICMP works (NSX-T implicitly allows for troubleshooting) but TCP blocked.
**Fix**: Set `enable_firewall = false` in T1 gateway resources.
**For Production**: Create explicit allow rules instead of disabling firewall.

### T0 Gateway Design Assumption
**Design Doc Assumption**: "T0 already configured with external connectivity"
**Reality**: Assumption was CORRECT - T0 uplinks exist from VCF VPC deployment (VLAN 70).
**Network Topology**: Shared T0 gateway approach (same as VPC configuration).

### Ops Manager OVA Deployment
**Critical**: Use `govc import.spec` to extract proper vApp property schema.
**Don't**: Manually create JSON - structure may be incorrect.
**Authentication**: OVA only supports SSH keys, no password property.

## Diagnostic Scripts
Created in `/tmp/`:
- `check-t0-config.sh`: T0 gateway config
- `check-t1-config.sh`: T1 router config
- `check-all-segments.sh`: List all NSX-T segments
- `check-vlan-segments.sh`: VLAN segments and routing
- `check-actual-t1-firewall.sh`: T1 firewall rules
- `test-connectivity.sh`: Network connectivity tests

## References
- **VCF VPC Guide**: https://williamlam.com/2025/07/ms-a2-vcf-9-0-lab-configuring-nsx-virtual-private-cloud-vpc.html
- **Design Doc**: `docs/plans/2025-11-25-tas-vcf-design.md`
- **Implementation Plan**: `docs/plans/2025-12-01-tas-vcf-implementation.md`
