# TAS VPC Migration Plan

## Overview

Migrate TAS from traditional NSX-T segment-based networking to NSX VPC architecture, based on proven working configuration from William Lam's VPC guide.

## Problem Statement

Current TAS deployment using traditional NSX-T segments experiences TCP connectivity failures:
- ICMP works through NAT
- TCP (SSH/HTTPS) fails consistently
- Issue persists across multiple Ops Manager deployments
- Root cause: Unknown incompatibility between Ops Manager OVA and NSX-T overlay segments

## Proven Solution

William Lam's VPC configuration successfully deployed VMs with full TCP connectivity. This approach uses VPC External IP assignment instead of DNAT, providing simpler and more reliable networking.

## Architecture Comparison

### Current (Broken)
```
Internet → T0 Gateway → DNAT → T1 Gateway → Overlay Segment → Ops Manager VM
                       31.31.10.10 → 10.0.1.10
```

### Proposed (VPC)
```
Internet → T0 Gateway → VPC Gateway → VPC Subnet → Ops Manager VM
                                                     (Direct External IP from VPC Block)
```

## VPC Design for TAS

### VPC Configuration

**VPC Name**: `tas-vpc`
**Private CIDR**: `172.20.0.0/16` (internal addressing)
**External IP Block**: Reuse existing `31.31.10.0/24` or allocate new block
**Gateway Mode**: Centralized Connectivity Gateway (required for vSphere)
**Edge Cluster**: `ec-01` (existing)

### Subnet Design

| Subnet Name | Type | CIDR | Purpose | DHCP |
|-------------|------|------|---------|------|
| tas-vpc-infrastructure | Private | 172.20.1.0/24 | Ops Manager, BOSH Director | Enabled |
| tas-vpc-deployment | Private | 172.20.2.0/24 | TAS Runtime VMs | Enabled |
| tas-vpc-services | Private | 172.20.3.0/24 | Service Instances | Enabled |

### External IP Allocation Strategy

**Option A: Public Subnets** (Use external IPs directly)
- Subnets allocated from VPC External IP Block
- VMs get routable IPs automatically
- Simpler but uses more external IPs

**Option B: Private Subnets + Assign External IP** (Recommended)
- Subnets use private CIDR
- Manually assign external IPs to specific VMs (Ops Manager, load balancers)
- More efficient IP usage
- Matches traditional TAS deployment model

### External IP Assignments

Using "Assign External IP" feature for:
- **Ops Manager**: 31.31.10.10
- **Web LB VIP**: 31.31.10.20
- **SSH LB VIP**: 31.31.10.21
- **TCP LB VIP**: 31.31.10.22

## Implementation Steps

### Phase 1: VPC Infrastructure (Manual via NSX UI)

1. **Create VPC External IP Block** (if not exists)
   - Navigate to: Networking → IP Address Management → IP Address Blocks
   - Create block: `31.31.10.0/24` (or verify existing)

2. **Create VPC**
   - Navigate to: Networking → Virtual Private Clouds
   - Click "Add VPC"
   - Name: `tas-vpc`
   - Private IPv4 CIDR: `172.20.0.0/16`
   - VPC External IP Block: Select `31.31.10.0/24`
   - Enable "Centralized Connectivity Gateway"
   - Edge Cluster: `ec-01`
   - T0 Gateway: `transit-gw`

3. **Create Subnets**
   - Right-click `tas-vpc` → New Subnet
   - Create three subnets per table above
   - Enable DHCP on all subnets
   - Set DNS: `192.168.10.2`

4. **Configure External Connectivity**
   - Verify VPC has default route to T0
   - Test connectivity from VPC subnet

### Phase 2: Terraform Configuration

Create Terraform module to manage VPC resources programmatically for future modifications:
- VPC subnets
- External IP assignments
- Security policies
- Load balancer configuration

### Phase 3: Ops Manager Deployment to VPC

1. **Deploy Ops Manager OVA**
   - Network: Select VPC subnet `tas-vpc-infrastructure`
   - IP: Use DHCP initially

2. **Assign External IP**
   - Right-click VM → Assign External IP
   - Select: `31.31.10.10`

3. **Test Connectivity**
   - ICMP: `ping 31.31.10.10`
   - SSH: `ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@31.31.10.10`
   - HTTPS: `curl -k https://31.31.10.10`

4. **If successful, configure Ops Manager**
   - Access web UI
   - Configure authentication
   - Set up BOSH Director

### Phase 4: Cleanup

1. **Remove old NSX-T resources**
   - Delete T1 gateways (tas-T1-*)
   - Delete segments (tas-Infrastructure, tas-Deployment, tas-Services)
   - Remove NAT rules on T0
   - Clean up IP pools/blocks

2. **Update documentation**
   - Update CLAUDE.md with VPC architecture
   - Document lessons learned

## Prerequisites

### Existing Infrastructure (Reuse)
- ✅ T0 Gateway: `transit-gw` (with VLAN 70 uplinks)
- ✅ Edge Cluster: `ec-01`
- ✅ External routing: 0.0.0.0/0 → 172.30.70.1

### New Requirements
- VPC feature enabled in NSX (should be available in VCF 9)
- External IP block configured
- Understanding of VPC subnet types (public vs private)

## Migration Strategy

**Recommended Approach**: Parallel deployment
1. Keep existing NSX-T segments running
2. Create VPC infrastructure alongside
3. Deploy Ops Manager to VPC
4. Verify full functionality
5. Only then remove old segments

**Rollback Plan**: If VPC doesn't work
- Old segments still exist
- Can redeploy to traditional segments
- No data loss (Ops Manager not configured yet)

## Success Criteria

- [ ] VPC created with all three subnets
- [ ] External IP block configured
- [ ] Ops Manager deployed to VPC subnet
- [ ] External IP assigned to Ops Manager
- [ ] SSH connectivity works (port 22)
- [ ] HTTPS connectivity works (port 443)
- [ ] Ops Manager web UI accessible
- [ ] DNS resolution works (opsman.tas.vcf.lab)

## Risk Assessment

**Low Risk**:
- VPC already proven in your environment
- Parallel deployment allows testing without disruption
- Easy rollback if needed

**Concerns**:
- VPC feature availability/licensing in VCF 9
- Learning curve for VPC management
- Potential Terraform provider support for VPC

## References

- William Lam's VPC Guide: https://williamlam.com/2025/07/ms-a2-vcf-9-0-lab-configuring-nsx-virtual-private-cloud-vpc.html
- Current broken setup: `docs/plans/2025-12-01-tas-vcf-implementation.md`
- Troubleshooting doc: `troubleshooting/ops-manager-tcp-connectivity-issue.md`

## Next Steps

1. Verify VPC exists from your William Lam test
2. Create TAS VPC (manual via NSX UI)
3. Test with simple Ubuntu VM first
4. Deploy Ops Manager if test succeeds
5. Document and automate with Terraform
