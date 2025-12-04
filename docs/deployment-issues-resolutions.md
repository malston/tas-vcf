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

### NSX-T Load Balancer Virtual Servers Not Attached to Service

**Date**: December 4, 2025
**Severity**: High - Blocks all HTTP/HTTPS traffic to TAS
**Status**: Resolved with Manual Workaround

#### Issue

After `terraform apply` created NSX-T load balancer infrastructure, HTTP/HTTPS virtual servers remained "Deactivated" and health checks never ran, causing all traffic to the load balancer VIPs to fail.

#### Symptoms

- Virtual servers show status "Deactivated" in NSX UI
- Pool members show status "Activated" but no health status (UP/DOWN)
- `curl http://31.31.10.20` times out completely
- `curl https://api.sys.tas.vcf.lab` fails with connection timeout
- Gorouter VMs are running and healthy (`/health` endpoint responds on port 8080)
- Health monitor configuration is correct (port 8080, path `/health`)
- Network connectivity works (VMs can reach gateway)

#### Root Cause

The NSX-T Policy API Terraform provider (`nsxt_policy_lb_virtual_server`) does NOT support attaching virtual servers to a load balancer service declaratively. The virtual servers are created but not associated with the `nsxt_policy_lb_service`, leaving them in a deactivated state.

**What Happened**:
1. Terraform created load balancer service attached to T1 gateway
2. Terraform created virtual servers with correct pools, IPs, ports
3. **But**: No parameter exists to attach virtual servers to the service
4. Virtual servers remained deactivated (no service to run on)
5. Health checks never started
6. Traffic to VIPs had no active endpoints

**Why It Happened**:
The `nsxt_policy_lb_virtual_server` resource lacks an `lb_service_path` parameter. The legacy API (`nsxt_lb_service`) supported this via `virtual_server_ids` parameter, but the modern Policy API doesn't provide a declarative way to create this association.

#### Resolution

**Manual attachment required after `terraform apply`:**

1. Navigate to **NSX UI → Networking → Load Balancing → Load Balancers → Virtual Servers**

2. For EACH virtual server (tas-web-http-vs, tas-web-https-vs, tas-ssh-vs, tas-tcp-router-vs):
   - Click virtual server name
   - Click **Edit**
   - Select `tas-lb-service` in the **Load Balancer** dropdown
   - Click **Save**

3. Wait 15-30 seconds for virtual servers to transition from "In Progress" to "Success"

4. Verify health checks start running and pool members show health status

**Verification**:

```bash
# Test HTTP connectivity (should return 400 from gorouter if no apps deployed)
curl -I http://31.31.10.20

# Test HTTPS connectivity (TLS handshake should complete)
curl -k https://api.sys.tas.vcf.lab

# Check in NSX UI:
# - Virtual servers show "Success" status
# - Pool members show "UP" health status
```

**Expected Behavior After Fix**:
- `curl http://31.31.10.20` → `HTTP 400 Bad Request` (gorouter can't route without apps)
- This is SUCCESS - proves load balancer works, traffic reaches gorouters
- The 400 is expected when no apps are deployed yet

#### Lesson Learned

**Terraform NSX-T Policy API Limitation**:

The modern NSX-T Policy API resources (`nsxt_policy_*`) don't support declarative virtual server attachment. This differs from the legacy API:

- **Legacy API** (`nsxt_lb_service`): Has `virtual_server_ids` parameter ✅
- **Policy API** (`nsxt_policy_lb_service`): No attachment parameter ❌

**Workaround Options**:

1. **Accept manual step** (recommended): Use Policy API, manually attach virtual servers after terraform apply
2. **Use legacy API**: Switch to deprecated `nsxt_lb_*` resources with `virtual_server_ids`
3. **Post-terraform automation**: Script NSX-T API calls to attach virtual servers

**Key Indicators of This Issue**:
- Virtual servers show "Deactivated" in NSX UI
- Pool members show administrative state but no health status
- ICMP to VIP works but TCP connections time out
- Gorouter VMs are healthy and listening on correct ports
- Health monitor configuration is correct

**Prevention**:
- Document requirement to manually attach virtual servers after terraform apply
- Consider creating a post-terraform script to automate attachment via NSX-T API
- Or convert to legacy API resources if declarative attachment is critical

#### References

- **Comparison**: TAS ICM Paving uses legacy API with `virtual_server_ids` parameter
- **Legacy Example**: `~/workspace/tas-icm-paving/nsxt/pas-lbs.tf` - Shows `nsxt_lb_service` with `virtual_server_ids`
- **Related Files**:
  - `terraform/nsxt/load_balancer.tf` - Virtual server and service definitions (Policy API)
  - `docs/deployment-issues-resolutions.md` - This document

---

## Contributing

When documenting new issues, include:
1. Clear symptom description (what you observed)
2. Root cause analysis (why it happened)
3. Step-by-step resolution (how to fix)
4. Verification steps (how to confirm fix)
5. Lessons learned (how to prevent)

This helps build institutional knowledge and reduces troubleshooting time for similar issues.
