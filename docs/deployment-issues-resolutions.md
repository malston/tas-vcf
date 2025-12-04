# TAS Deployment Issues & Resolutions

This document captures issues encountered during TAS deployment and their resolutions, serving as a troubleshooting guide for similar problems.

## Overview

Each issue is documented with:
- **Symptoms**: Observable behavior
- **Root Cause**: Technical explanation
- **Resolution**: Step-by-step fix
- **Lesson Learned**: Key takeaways to prevent recurrence

## Issues

### Missing NSX-T Load Balancer Pool Registration

**Date**: December 4, 2025
**Severity**: High - Blocks TAS API access
**Status**: Resolved

#### Issue

TAS smoke tests failed with `dial tcp 31.31.10.20:443: i/o timeout` when attempting to connect to `api.sys.tas.vcf.lab`.

#### Symptoms

- DNS resolution works correctly (`api.sys.tas.vcf.lab` → `31.31.10.20`)
- ICMP ping to VIP fails with "Time to live exceeded" (routing loop)
- NSX-T shows load balancer virtual server as "deactivated"
- NSX-T shows load balancer pool as "deactivated"
- Gorouter VMs are running and healthy in BOSH
- No error messages in deployment logs

#### Root Cause

The NSX-T load balancer pools were created by terraform, but the TAS tile configuration lacked the `nsxt.lb.server_pools` setting that tells BOSH to register router VMs to those pools.

**What Happened**:
1. Terraform created the NSX-T infrastructure (pools, virtual servers, VIPs)
2. BOSH Director had NSX-T networking enabled
3. TAS deployed gorouter VMs successfully
4. **But**: Gorouters never registered to the NSX load balancer pool
5. NSX automatically deactivated the pool and virtual server (no healthy members)
6. Traffic to the VIP had nowhere to route

**Why It Happened**:
The initial TAS configuration was missing the pool membership configuration. This is a common oversight when setting up NSX-T integration because the configuration happens at three different layers (terraform, BOSH Director, TAS tile), and it's easy to miss one.

#### Resolution

Add the NSX-T load balancer pool configuration to the router resource in `foundations/vcf/config/tas.yml`:

```yaml
resource-config:
  router:
    instances: automatic
    instance_type:
      id: automatic
    nsxt:
      lb:
        server_pools:
          - name: tas-gorouter-pool
            port: 443
          - name: tas-gorouter-pool
            port: 80
```

**Steps to Apply**:

1. Add the configuration to `tas.yml` (shown above)
2. Apply the TAS configuration:
   ```bash
   bin/06-configure-tas.sh
   ```
3. Deploy the changes:
   ```bash
   bin/07-apply-tas-changes.sh
   ```
4. Verify in BOSH manifest that vm_extensions are created
5. Wait for deployment to complete

**Verification**:

After deployment completes:
1. BOSH registers gorouter VMs to the NSX load balancer pool
2. NSX detects healthy pool members
3. Pool and virtual server activate automatically
4. Traffic flows correctly to `api.sys.tas.vcf.lab`
5. Smoke tests pass

```bash
# Check NSX pool status (via NSX UI)
# Navigate to: Networking → Load Balancing → Server Pools → tas-gorouter-pool
# Should show: Status = Up, Members = 1 (or more), Health = UP

# Test connectivity
curl -k https://api.sys.tas.vcf.lab
# Should return API response (not timeout)

# Check BOSH VMs
bosh -e <director> -d cf-<guid> vms
# Should show router VMs as "running"
```

#### Lesson Learned

**NSX-T integration requires three layers of configuration:**

1. **NSX-T Infrastructure** (Terraform)
   - Create pools, virtual servers, VIPs
   - Located in: `terraform/nsxt/load_balancer.tf`

2. **BOSH Director** (Director Config)
   - Enable NSX-T networking
   - Configuration: `nsx_networking_enabled: true`
   - Located in: `foundations/vcf/config/director.yml`

3. **TAS Tile** (Product Config)
   - Configure pool membership for specific jobs
   - Configuration: `nsxt.lb.server_pools` in `resource-config`
   - Located in: `foundations/vcf/config/tas.yml`

**Missing any layer results in non-functional load balancing**, even though individual components appear healthy.

**Key Indicators of This Issue**:
- Load balancer virtual server shows as "deactivated" in NSX
- Pool shows as "deactivated" with zero members
- VMs are running and healthy in BOSH
- No errors in BOSH deployment logs
- DNS resolves correctly but TCP connections timeout

**Prevention**:
When setting up NSX-T integration, always verify all three layers are configured:
1. Check terraform output for pool paths
2. Verify Director has `nsx_networking_enabled: true`
3. Confirm TAS tile has `nsxt.lb.server_pools` for router jobs

#### References

- **Commit**: `ae2d4b0` - "Add NSX-T load balancer pool configuration for gorouters"
- **Documentation**: [Deploying TAS with NSX-T Networking](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/vsphere-nsx-t.html)
- **Related Files**:
  - `terraform/nsxt/load_balancer.tf` - Pool creation
  - `foundations/vcf/config/director.yml` - NSX-T enablement
  - `foundations/vcf/config/tas.yml` - Pool membership

---

## Contributing

When documenting new issues, include:
1. Clear symptom description (what you observed)
2. Root cause analysis (why it happened)
3. Step-by-step resolution (how to fix)
4. Verification steps (how to confirm fix)
5. Lessons learned (how to prevent)

This helps build institutional knowledge and reduces troubleshooting time for similar issues.
