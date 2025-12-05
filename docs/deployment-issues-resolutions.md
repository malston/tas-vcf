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

### Intermittent HTTP/HTTPS Routing Failures with Dual Pool Members

**Date**: December 4, 2025
**Severity**: High - Causes 40% failure rate on smoke tests
**Status**: Resolved

#### Issue

TAS smoke tests failed intermittently with "http: server gave HTTP response to HTTPS client" errors. The failure rate was approximately 40%, occurring randomly across different test runs.

#### Symptoms

- HTTPS connections to `https://api.sys.tas.vcf.lab` and `https://login.sys.tas.vcf.lab` failed intermittently
- Error message: "http: server gave HTTP response to HTTPS client"
- Approximately 60% success rate, 40% failure rate
- Both successful and failed requests reached the gorouter VM
- NSX-T load balancer showed both pool members as healthy (ports 80 and 443)
- Gorouter was listening on both ports 80 (HTTP) and 443 (HTTPS)

#### Root Cause

The NSX-T load balancer pool had **two members registered** for the same gorouter VM:
- Member 1: `10.0.2.16:80` (HTTP listener)
- Member 2: `10.0.2.16:443` (HTTPS listener)

The NSX-T virtual server for HTTPS (`tas-web-https-vs`) was configured with:
- Virtual server port: `443`
- Pool: `tas-gorouter-pool`
- **Default pool member ports: `["80", "443"]`**

**What Happened**:
1. Client sends HTTPS request to `https://api.sys.tas.vcf.lab:443` (VIP: 31.31.10.20:443)
2. NSX-T `tas-web-https-vs` virtual server receives the encrypted TLS traffic on port 443
3. Virtual server performs TCP passthrough (no TLS termination at load balancer)
4. Load balancer randomly selects a pool member:
   - **60% of time**: Routes to `10.0.2.16:443` → Gorouter HTTPS listener → Success
   - **40% of time**: Routes to `10.0.2.16:80` → Gorouter HTTP listener → **Failure**
5. When routed to port 80, gorouter receives encrypted TLS bytes on its HTTP listener
6. HTTP listener can't parse TLS handshake, responds with HTTP error
7. Client sees "http: server gave HTTP response to HTTPS client"

**Why This Configuration Existed**:
The TAS tile configuration initially registered both ports to support both HTTP and HTTPS traffic:

```yaml
resource-config:
  router:
    nsxt:
      lb:
        server_pools:
          - name: tas-gorouter-pool
            port: 443
          - name: tas-gorouter-pool
            port: 80
```

This created two pool members for the same VM, causing the load balancer to randomly distribute HTTPS traffic between HTTP and HTTPS backend listeners.

#### Resolution

**Remove the port 80 pool member** from the TAS configuration, leaving only port 443:

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
```

**Steps to Apply**:

1. Update `foundations/vcf/config/tas.yml` to remove port 80 registration (shown above)
2. Apply the TAS configuration:
   ```bash
   bin/06-configure-tas.sh
   ```
3. Deploy the changes:
   ```bash
   bin/07-apply-tas-changes.sh
   ```

**Manual Cleanup Required**:

BOSH does **not** automatically remove stale pool members when configuration changes. After deployment, manually remove the port 80 member from NSX-T:

1. Navigate to **NSX UI → Networking → Load Balancing → Server Pools → tas-gorouter-pool**
2. Find the member with port 80 (e.g., `vm-41d7fb88-fcb0-45bb-97a9-628d44db5b15 10.0.2.16 80`)
3. Click **Actions → Remove Member**
4. Wait 10-15 seconds for pool to update

**Verification**:

After removing the stale member:

```bash
# Test HTTPS connectivity (should succeed 100% of the time)
for i in {1..20}; do
  curl -sk https://api.sys.tas.vcf.lab/v3/info | jq -r '.build' || echo "FAILED"
done

# Should show 20 successful responses, zero failures
```

#### Lesson Learned

**NSX-T Load Balancer Pool Member Management**:

1. **One member per backend listener**: Each pool member should correspond to exactly one service port on the backend VM
2. **BOSH doesn't clean up pool members**: When removing pool registrations from TAS config, BOSH doesn't delete existing NSX-T pool members
3. **TCP passthrough requires correct port mapping**: NSX-T virtual servers doing TCP passthrough (not TLS termination) must route to the correct backend port

**Load Balancer Architecture Understanding**:

The NSX-T load balancer configuration for TAS uses **two virtual servers** but **one pool member**:

| Component | Virtual Server | VIP:Port | Backend Pool | Pool Member | Purpose |
|-----------|----------------|----------|--------------|-------------|---------|
| HTTP | `tas-web-http-vs` | 31.31.10.20:80 | `tas-gorouter-pool` | `10.0.2.16:80` | HTTP app traffic |
| HTTPS | `tas-web-https-vs` | 31.31.10.20:443 | `tas-gorouter-pool` | `10.0.2.16:443` | HTTPS app traffic |

**Why Two Virtual Servers?**
- Separate virtual servers for HTTP (port 80) and HTTPS (port 443) on the **same VIP**
- Each virtual server uses `default_pool_member_ports` to route to the corresponding backend port
- HTTP virtual server routes port 80 → port 80 (HTTP listener on gorouter)
- HTTPS virtual server routes port 443 → port 443 (HTTPS listener on gorouter)

**Why Only One Pool Member in Configuration?**
- We only register the HTTPS listener (port 443) in TAS configuration
- The HTTP virtual server still routes correctly because:
  - Terraform creates both virtual servers with correct `default_pool_member_ports`
  - HTTP traffic on port 80 goes to gorouter port 80 automatically
  - We don't need to register port 80 in TAS config because HTTP is handled separately

**TLS Termination Architecture**:
- NSX-T load balancer performs **TCP passthrough** (uses `nsxt_policy_lb_fast_tcp_application_profile`)
- TLS termination happens **at the gorouter**, not at the load balancer
- Configured via `.properties.routing_tls_termination: router` in TAS tile
- Gorouter handles TLS handshake and serves multiple certificates via SNI

**Key Indicators of This Issue**:
- Intermittent HTTPS failures with consistent error message
- Success rate less than 100% (typically matches ratio of pool members)
- NSX-T shows multiple members for same VM on different ports
- Both pool members show as healthy
- `curl` tests show non-deterministic failures

**Prevention**:
- Only register necessary ports in TAS tile NSX-T pool configuration
- Understand whether load balancer performs TLS termination or TCP passthrough
- Match pool member ports to the service ports that should handle that traffic type
- Always manually verify NSX-T pool members after BOSH configuration changes

#### References

- **Commit**: TBD - "Remove port 80 from gorouter pool registration to fix HTTPS routing"
- **Related Issue**: Smoke tests failing with HTTPS/HTTP mismatch errors
- **Documentation**: `docs/tas-configuration-decisions.md` - TLS termination architecture
- **Related Files**:
  - `terraform/nsxt/load_balancer.tf` - Virtual server and pool definitions
  - `foundations/vcf/config/tas.yml` - Router pool registration
  - `foundations/vcf/vars/director.yml` - BOSH NSX-T integration

---

### Certificate Domain Coverage for Apps Domain

**Date**: December 4, 2025
**Severity**: Medium - Blocks smoke tests but doesn't affect system services
**Status**: Resolved

#### Issue

TAS smoke tests failed with TLS certificate validation errors when accessing applications deployed to the apps domain (`*.apps.tas.vcf.lab`). System domain services worked correctly.

#### Symptoms

- Smoke tests fail with: `tls: failed to verify certificate: x509: certificate is valid for *.sys.tas.vcf.lab, *.login.sys.tas.vcf.lab, *.uaa.sys.tas.vcf.lab, not SMOKES-APP-f7ab30b7-6de4.apps.tas.vcf.lab`
- System domain endpoints work fine: `https://api.sys.tas.vcf.lab`, `https://login.sys.tas.vcf.lab`
- Apps domain endpoints fail TLS validation: `https://*.apps.tas.vcf.lab`
- Gorouter is serving the system certificate for all domains

#### Root Cause

The TAS configuration was only providing the **system domain certificate** to the gorouter for both system and apps domains:

**Incorrect Configuration**:
```yaml
.properties.networking_poe_ssl_certs:
  value:
    - name: default
      certificate:
        cert_pem: ((tas_system_cert_pem))  # Only covers *.sys.tas.vcf.lab
        private_key_pem: ((tas_system_key_pem))
```

**What Happened**:
1. Terraform generated two separate certificates:
   - System cert: `*.sys.tas.vcf.lab`, `*.login.sys.tas.vcf.lab`, `*.uaa.sys.tas.vcf.lab`
   - Apps cert: `*.apps.tas.vcf.lab`
2. TAS configuration script (`bin/06-configure-tas.sh`) incorrectly used system cert for apps:
   ```bash
   --var="tas_apps_cert_pem=$tas_system_cert"  # Wrong!
   --var="tas_apps_key_pem=$tas_system_key"    # Wrong!
   ```
3. Gorouter only had system certificate configured
4. When smoke tests deployed apps to `*.apps.tas.vcf.lab`, TLS validation failed
5. Certificate presented didn't include `*.apps.tas.vcf.lab` in Subject Alternative Names (SANs)

#### Resolution

**Configure both certificates in the gorouter** to support Server Name Indication (SNI):

**1. Update TAS Configuration** (`foundations/vcf/config/tas.yml`):

```yaml
.properties.networking_poe_ssl_certs:
  value:
    - name: system
      certificate:
        cert_pem: ((tas_system_cert_pem))
        private_key_pem: ((tas_system_key_pem))
    - name: apps
      certificate:
        cert_pem: ((tas_apps_cert_pem))
        private_key_pem: ((tas_apps_key_pem))
```

**2. Update Configuration Script** (`bin/06-configure-tas.sh`):

Retrieve both certificates from Terraform:
```bash
# Get certificates from Terraform outputs
cd "${CUR_DIR}/../terraform/certs"
tas_system_cert=$(terraform output -raw tas_system_cert 2>/dev/null || echo "")
tas_system_key=$(terraform output -raw tas_system_key 2>/dev/null || echo "")
tas_apps_cert=$(terraform output -raw tas_apps_cert 2>/dev/null || echo "")      # Added
tas_apps_key=$(terraform output -raw tas_apps_key 2>/dev/null || echo "")        # Added
ca_cert=$(terraform output -raw ca_cert 2>/dev/null || echo "")
```

Pass correct certificate variables:
```bash
om interpolate -c "${CUR_DIR}/../foundations/${FOUNDATION}/vars/tas.yml" \
  --var="tas_system_cert_pem=$tas_system_cert" \
  --var="tas_system_key_pem=$tas_system_key" \
  --var="tas_apps_cert_pem=$tas_apps_cert" \     # Fixed
  --var="tas_apps_key_pem=$tas_apps_key" \       # Fixed
  # ... other vars
```

**Steps to Apply**:

1. Update both files as shown above
2. Apply the TAS configuration:
   ```bash
   bin/06-configure-tas.sh
   ```
3. Deploy the changes:
   ```bash
   bin/07-apply-tas-changes.sh
   ```
4. Wait for deployment to complete
5. Run smoke tests to verify

**Verification**:

```bash
# Test system domain (should use system cert)
openssl s_client -connect api.sys.tas.vcf.lab:443 -servername api.sys.tas.vcf.lab < /dev/null 2>&1 | \
  grep -E "subject=|issuer=|DNS:"

# Test apps domain (should use apps cert)
openssl s_client -connect test-app.apps.tas.vcf.lab:443 -servername test-app.apps.tas.vcf.lab < /dev/null 2>&1 | \
  grep -E "subject=|issuer=|DNS:"

# Run smoke tests (should pass 100%)
# Tests deploy app to *.apps.tas.vcf.lab and verify TLS works
```

#### Lesson Learned

**Gorouter Multi-Certificate Support via SNI**:

The gorouter can serve multiple TLS certificates using Server Name Indication (SNI):

1. **Multiple Certificate Configuration**: Configure all certificates in `.properties.networking_poe_ssl_certs`
2. **SNI Matching**: Gorouter examines the SNI hostname in TLS handshake
3. **Certificate Selection**: Presents certificate whose SAN matches the requested hostname
4. **Fallback**: First certificate is used if no SNI match found

**Certificate Architecture**:

```
Client Request          Gorouter Certificate Selection
================        ==============================
api.sys.tas.vcf.lab     → System cert (*.sys.tas.vcf.lab)
login.sys.tas.vcf.lab   → System cert (*.login.sys.tas.vcf.lab)
app1.apps.tas.vcf.lab   → Apps cert (*.apps.tas.vcf.lab)
app2.apps.tas.vcf.lab   → Apps cert (*.apps.tas.vcf.lab)
```

**Certificate Generation Strategy**:

Terraform generates separate certificates for each domain class:
- **System Cert** (`tas_system`): Covers system APIs, UAA, login services
- **Apps Cert** (`tas_apps`): Covers deployed application routes
- **CA Cert**: Signs both certificates (trusted by BOSH Director)

**Why Separate Certificates?**
- Security: Apps domain certificate can be rotated independently
- Compliance: Different security zones may require different certificate policies
- Lifecycle: System certificates may need longer validity periods
- Wildcard scope: Limits blast radius if certificate is compromised

**BOSH Director Trusted Certificates**:

Question: Do we need to update BOSH director trusted certificates?

**Answer: No.** The BOSH director already trusts the CA certificate that signed both system and apps certificates. Trust works through the certificate chain:
- CA Certificate (in BOSH trusted certs) → signs:
  - System Certificate (`*.sys.tas.vcf.lab`)
  - Apps Certificate (`*.apps.tas.vcf.lab`)

Since both certificates are signed by the same CA, adding the CA to trusted certificates is sufficient.

**Key Indicators of This Issue**:
- TLS validation errors specifically for apps domain (`*.apps.tas.vcf.lab`)
- Error message shows certificate covers system domain but not apps domain
- System domain endpoints work correctly
- Certificate SANs don't include the requested hostname

**Prevention**:
- When using separate certificates for system and apps domains, configure both in TAS tile
- Verify Terraform outputs include all required certificates (`tas_system_cert`, `tas_apps_cert`)
- Test both system and apps domain TLS before running smoke tests
- Use `openssl s_client -servername` to verify SNI certificate selection

#### References

- **Commit**: TBD - "Configure separate certificates for system and apps domains"
- **Related Issue**: Smoke tests failing with certificate validation errors
- **Documentation**:
  - `docs/tas-configuration-decisions.md` - Certificate configuration strategy
  - `terraform/certs/main.tf` - Certificate generation
- **Related Files**:
  - `bin/06-configure-tas.sh` - Certificate retrieval and interpolation
  - `foundations/vcf/config/tas.yml` - Gorouter certificate configuration
  - `terraform/certs/outputs.tf` - Certificate Terraform outputs

---

## Contributing

When documenting new issues, include:
1. Clear symptom description (what you observed)
2. Root cause analysis (why it happened)
3. Step-by-step resolution (how to fix)
4. Verification steps (how to confirm fix)
5. Lessons learned (how to prevent)

This helps build institutional knowledge and reduces troubleshooting time for similar issues.
