# TAS Configuration Decision Making Process

## Overview

This document explains the decision-making process for determining configuration settings in the Small Footprint TAS 6.0.6 tile for deployment to VCF 9.

## Information Sources

### Primary Sources
1. **Design Document**: `docs/plans/2025-11-25-tas-vcf-design.md`
   - Network architecture (T0/T1/Segments)
   - IP addressing scheme
   - Load balancer configuration
   - NSX-T integration requirements

2. **Implementation Plan**: `docs/plans/2025-12-01-tas-vcf-implementation.md`
   - Deployment approach
   - Terraform state and outputs
   - Automation strategy

3. **Broadcom TechDocs**:
   - [Configuring TAS for VMs](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/toc-tas-install-features-index.html)
   - [Deploying TAS with NSX-T Networking](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/vsphere-nsx-t.html)
   - [TAS for VMs Resource Requirements](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/requirements.html)

4. **Existing Infrastructure**:
   - Terraform outputs (`terraform/nsxt/`, `terraform/vsphere/`, `terraform/certs/`)
   - BOSH Director configuration
   - Ops Manager setup

## Configuration Decision Framework

### Important: Small Footprint TAS Property Differences

**Critical Discovery**: Small Footprint TAS (product name `cf`) has different property names and structure than regular TAS (product name `srt`). This significantly impacted our configuration process.

**Key Differences**:

1. **NSX-T Integration Location**:
   - ❌ **NOT in TAS tile**: `.properties.nsx_networking.*` properties don't exist
   - ✅ **In BOSH Director**: NSX-T is configured at the IaaS level in Director configuration
   - Result: All NSX-T connection details (host, username, password, CA cert) are in Director config only

2. **CredHub Encryption**:
   - ❌ Regular TAS: `.properties.credhub_key_encryption_passwords`
   - ✅ Small Footprint TAS: `.properties.credhub_internal_provider_keys`

3. **Diego Cell Capacity**:
   - ❌ Regular TAS: `.properties.diego_cell_disk_capacity` and `.properties.diego_cell_memory_capacity`
   - ✅ Small Footprint TAS: `.diego_cell.executor_disk_capacity` and `.diego_cell.executor_memory_capacity`
   - Note: These are component-level properties, not under `.properties`

4. **Load Balancer Configuration**:
   - vSphere with NSX-T: Load balancer pool membership handled automatically by BOSH via NSX-T integration
   - No explicit load balancer configuration needed in TAS tile for vSphere

5. **Required Fields**:
   - `.mysql_monitor.recipient_email` - Required field for MySQL monitoring alerts (even in lab environments)

6. **System Logging**:
   - `.properties.system_logging` - Exists but is non-configurable, omit from configuration

**Property Discovery**: Use `om curl -p /api/v0/staged/products/<product-guid>/properties` to get actual available properties for the specific tile version.

## Critical Defaults Overridden

This section documents configuration defaults that were deliberately overridden and the rationale for each decision. These represent lessons learned during deployment.

### NSX-T T1 Gateway Firewall Configuration

**Default**: T1 gateways have `enable_firewall = true` with no rules defined
**Override**: Set `enable_firewall = false` in `terraform/nsxt/t1_gateways.tf`

**Why Changed**:
- **The Silent Failure Pattern**: Enabling firewalls without rules creates a default DENY-ALL policy
- ICMP succeeds (NSX-T implicitly allows for troubleshooting) but TCP traffic silently times out
- No error message indicates firewall is the cause - extremely difficult to diagnose
- Symptom: Ops Manager VM responded to ping but SSH/HTTPS connections timed out

**Configuration** (all three T1 gateways):
```terraform
resource "nsxt_policy_tier1_gateway" "tas_infrastructure" {
  enable_firewall = false  # Override: Disable rather than leave with no rules
  # ... other settings
}
```

**For Production**: Create explicit firewall rules instead of disabling. Never enable firewalls without rules.

**Affected Lines**:
- `terraform/nsxt/t1_gateways.tf:394` (Infrastructure T1)
- `terraform/nsxt/t1_gateways.tf:412` (Deployment T1)
- `terraform/nsxt/t1_gateways.tf:430` (Services T1)

### NSX-T Licensing Constraint

**Limitation Discovered**: NSX-T in this environment can only create **stateless firewall rules**
**Impact**: Cannot use connection state tracking (which most firewalls do by default)
**Root Cause**: Missing security license for NSX-T
**Decision**: Disable T1 firewalls entirely rather than attempt fragile stateless rules

**Why This Matters**:
- Stateful firewalls track TCP connections (SYN/ACK/FIN state machine)
- Stateless rules must explicitly allow both directions of traffic
- Very difficult to secure correctly without state tracking
- Influenced decision to use `enable_firewall = false`

### T1 Gateway Failover Mode Configuration

**Default**: NSX-T T1 gateways use `NON_PREEMPTIVE` failover mode
**Override**: Set Infrastructure T1 to `PREEMPTIVE` mode

**Why Changed**:
```terraform
# Infrastructure T1 (Ops Manager, BOSH Director)
failover_mode = "PREEMPTIVE"  # Override: Ops Manager state consistency is critical

# Deployment T1 (Diego cells, application workloads)
failover_mode = "NON_PREEMPTIVE"  # Keep default: App VMs can tolerate brief outages

# Services T1 (Service instances)
failover_mode = "NON_PREEMPTIVE"  # Keep default: Eventual consistency acceptable
```

**Rationale**:
- **Infrastructure**: Ops Manager and BOSH Director require consistent state; preemptive failover ensures fastest recovery
- **Deployment/Services**: Application VMs can reschedule; non-preemptive avoids unnecessary failovers during edge maintenance
- Trade-off: Preemptive causes more frequent failovers but ensures fastest recovery

### NSX-T Load Balancer SNAT Configuration

**Default**: Load balancer pools use `TRANSPARENT` SNAT (no source address translation)
**Override**: Different SNAT modes per workload type

**Configuration**:
```terraform
# GoRouter pool - Override to AUTOMAP
snat_mode = "AUTOMAP"  # Each VM gets its own SNAT IP (Kubernetes-style)

# TCP Router pool - Keep TRANSPARENT
snat_mode = "TRANSPARENT"  # Preserves source IPs for debugging

# Diego SSH pool - Keep TRANSPARENT
snat_mode = "TRANSPARENT"  # SSH sessions need real client IPs
```

**Why Changed**:
- **AUTOMAP for GoRouter**: Prevents port exhaustion from HTTP connection pooling; each Diego cell gets its own outbound IP
- **TRANSPARENT for TCP Router**: Real client IPs essential for application logging and security
- **TRANSPARENT for SSH Proxy**: Client IP needed for audit logs and security policies

**Trade-offs**:
- AUTOMAP: Better for high-connection-count protocols (HTTP) but loses client IP visibility
- TRANSPARENT: Preserves client IPs but can exhaust NAT port ranges under heavy load

### Gorouter TLS Cipher Configuration

**Default**: Gorouter uses TLS 1.2 ciphers only
**Override**: Add TLS 1.3 cipher suites to support modern TLS negotiation
**Location**: `foundations/vcf/config/tas.yml:41`

**Why Changed**:
- **Symptom**: HTTPS connections to `api.sys.tas.vcf.lab:443` failed with TLS handshake errors
- **Root Cause**: Gorouter attempted TLS 1.3 negotiation but only had TLS 1.2 ciphers configured
- **Evidence**: `openssl s_client` showed `Protocol: TLSv1.3` but `Cipher is (NONE)` (handshake failed)
- **Impact**: Smoke tests failed with "Invalid SSL Cert" errors

**Configuration**:
```yaml
.properties.gorouter_ssl_ciphers:
  value: TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384
```

**What Changed**:
- **Before**: `ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384` (TLS 1.2 only)
- **After**: Added `TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384` (TLS 1.3 support)
- Maintains backward compatibility with TLS 1.2 clients

**Why TLS 1.3 Ciphers Matter**:
- TLS 1.3 and TLS 1.2 use different cipher suite naming conventions
- TLS 1.2: `ECDHE-RSA-AES128-GCM-SHA256` (key exchange + auth + cipher)
- TLS 1.3: `TLS_AES_128_GCM_SHA256` (cipher only, key exchange built into protocol)
- Attempting TLS 1.3 handshake without TLS 1.3 ciphers causes connection failure

**Commit**: `851f65f` (2025-12-04)

### BOSH Director Configuration Overrides

**Defaults Changed**: Multiple BOSH Director operational properties
**Location**: `foundations/vcf/config/director.yml:1745-1749`

**Configuration**:
```yaml
director_configuration:
  ntp_servers_string: pool.ntp.org        # Override: Essential for certificate validation
  resurrector_enabled: true                # Override: Auto-recover failed VMs
  post_deploy_enabled: true                # Override: Post-deploy scripts for logging
  retry_bosh_deploys: true                 # Override: Transient failures shouldn't be permanent
```

**Why Changed**:

1. **NTP Configuration** (`ntp_servers_string: pool.ntp.org`):
   - Default: No NTP servers configured
   - Impact: Time drift causes certificate validation failures, authentication issues
   - Essential for TLS/SSL to function correctly

2. **BOSH Resurrector** (`resurrector_enabled: true`):
   - Default: Disabled (VMs stay down after failure)
   - Impact: Manual intervention required for every VM failure
   - Auto-recovery improves availability in lab and production

3. **Post-Deploy Scripts** (`post_deploy_enabled: true`):
   - Default: Disabled
   - Impact: Logging and monitoring agents not configured
   - Needed for operational visibility

4. **Retry on Failure** (`retry_bosh_deploys: true`):
   - Default: Deployments fail immediately on transient errors
   - Impact: Network glitches cause permanent deployment failures
   - Retry logic handles temporary infrastructure issues

### vSphere DRS Rule Configuration

**Default**: DRS rules are mandatory (hard rules)
**Override**: Use soft (should) rules instead of mandatory (must) rules

**Configuration**:
```terraform
resource "vsphere_compute_cluster_vm_anti_affinity_rule" "tas_az1" {
  mandatory = false  # Override: Soft rule prevents deployment failures
  # ... other settings
}
```

**Why Changed**:
- **Hard Rules** (mandatory = true): VM placement fails if preferred host is unavailable
- **Soft Rules** (mandatory = false): vSphere tries to honor placement but won't block deployment
- Prevents cascading failures during host maintenance or failures
- Still achieves desired placement in normal operations

**Affected Resources**:
- AZ placement rules for Diego cells
- Infrastructure component separation rules
- All documented in `terraform/vsphere/`

### 1. Network Configuration

#### Decision: Use NSX-T Native Integration
**Rationale**:
- VCF 9 environment already has NSX-T deployed
- NSX-T provides native container networking via NCP (NSX Container Plugin)
- Eliminates need for separate overlay network
- Provides micro-segmentation and network policies
- Reduces operational complexity

**Configuration**:
```yaml
.properties.nsx_networking: "enable"
.properties.nsx_networking.enable.nsx_mode: "nsx-t"
.properties.nsx_networking.enable.nsx_policy_api: true
```

**Alternative Considered**:
- Flannel networking (default) - Rejected because NSX-T integration provides better network isolation and policy enforcement

#### Decision: Domain Names
**Rationale**:
- Follow standard TAS naming convention: `*.sys.DOMAIN` for system, `*.apps.DOMAIN` for apps
- Use `.vcf.lab` domain to match existing infrastructure
- Makes it clear these are TAS-specific domains

**Configuration**:
```yaml
.cloud_controller.system_domain: sys.tas.vcf.lab
.cloud_controller.apps_domain: apps.tas.vcf.lab
```

**DNS Requirements**:
- Wildcard DNS entries required: `*.sys.tas.vcf.lab` → 31.31.10.20 (Web LB VIP)
- Wildcard DNS entries required: `*.apps.tas.vcf.lab` → 31.31.10.20 (Web LB VIP)

### 2. NSX-T Integration Details

**IMPORTANT**: NSX-T integration for Small Footprint TAS is configured entirely at the BOSH Director level, **NOT in the TAS tile**. The `.properties.nsx_networking.*` properties do not exist in Small Footprint TAS.

#### Decision: NSX-T Integration at BOSH Director Level
**Rationale**:
- Small Footprint TAS uses BOSH Director's IaaS configuration for NSX-T integration
- NSX-T Manager connection details (host, username, password, CA cert) configured in Director
- Container networking uses Silk CNI plugin, not NSX-T NCP
- Load balancer pool membership handled automatically via BOSH NSX-T integration

**Configuration Location**: `foundations/vcf/config/director.yml`
```yaml
properties-configuration:
  iaas_configuration:
    nsx_networking_enabled: true
    nsx_mode: nsx-t
    nsx_address: nsx01.vcf.lab
    nsx_username: admin
    nsx_password: ((nsxt_password))
    nsx_ca_certificate: ((nsxt_ca_cert))
```

#### Decision: Container Network CIDR Blocks
**Rationale**:
- Need non-overlapping RFC1918 space for Silk overlay network
- `10.255.0.0/16` for Silk CNI plugin overlay (configured in TAS tile)
- Large enough for thousands of containers

**Configuration in TAS Tile**:
```yaml
.properties.container_networking_interface_plugin: silk
.properties.container_networking_interface_plugin.silk.network_cidr: 10.255.0.0/16
.properties.container_networking_interface_plugin.silk.network_mtu: 1454
```

**Note**: MTU set to 1454 to account for VXLAN encapsulation overhead (1500 - 46 bytes)

### 3. Load Balancer Configuration

#### Decision: Automatic Load Balancer Pool Membership via NSX-T
**Rationale**:
- NSX-T load balancers and pools already configured via Terraform
- BOSH Director NSX-T integration handles automatic VM registration with pools
- Load balancer pool membership managed via BOSH vm_extensions and NSX-T tags
- No explicit load balancer configuration needed in TAS tile

**Configuration**:
- Load balancer pools created via Terraform in `terraform/nsxt/`
- VMs automatically registered with pools via BOSH NSX-T integration
- No tile-level configuration required

**Load Balancer Architecture**:
| Component | NSX-T Pool | VIP | Purpose |
|-----------|------------|-----|---------|
| Gorouter | tas-gorouter-pool | 31.31.10.20:80,443 | HTTP/HTTPS app traffic |
| TCP Router | tas-tcp-router-pool | 31.31.10.22:1024-65535 | TCP app traffic |
| Diego Brain (SSH Proxy) | tas-ssh-pool | 31.31.10.21:2222 | SSH to containers |

**Note**: For production deployments requiring explicit pool membership, use BOSH vm_extensions in Director configuration.

### 4. Availability Zones

#### Decision: Use Two Availability Zones
**Rationale**:
- Follows TAS best practice of N+1 redundancy
- Maps to physical ESXi hosts via DRS rules
- Provides compute-level fault tolerance
- Resource pool isolation per AZ

**Configuration**:
```yaml
network-properties:
  network:
    name: tas-Deployment
  other_availability_zones:
    - name: az1
    - name: az2
  singleton_availability_zone:
    name: az1
```

**Physical Mapping** (from Terraform/vSphere):
- `az1` → Resource pool `tas-az1` → Host `esx02.vcf.lab`
- `az2` → Resource pool `tas-az2` → Host `esx03.vcf.lab`

**Singleton Placement**:
- Components that can't be horizontally scaled go to az1
- Examples: Cloud Controller clock, Diego BBS master

### 5. Certificate Configuration

#### Decision: Use Terraform-Generated Self-Signed Certificates
**Rationale**:
- Lab environment doesn't require CA-signed certificates
- Terraform certs module already created certificates
- Consistent certificate management
- Can be replaced with CA-signed certs later

**Configuration Sources**:
```bash
cd terraform/certs
terraform output -raw tas_system_cert   # *.sys.tas.vcf.lab
terraform output -raw tas_system_key
terraform output -raw ca_cert
```

**Certificate Requirements**:
- System domain cert: `*.sys.tas.vcf.lab` (Cloud Controller, UAA, etc.)
- Apps domain cert: `*.apps.tas.vcf.lab` (Application routes)
- UAA SAML cert: For UAA service provider

**Configuration**:
```yaml
.properties.networking_poe_ssl_certs:
  value:
    - name: tas_system_cert
      certificate:
        cert_pem: ((tas_system_cert_pem))
        private_key_pem: ((tas_system_key_pem))
```

### 6. CredHub Encryption

#### Decision: Generate Random 32-byte Encryption Key
**Rationale**:
- CredHub requires encryption key for securing credentials
- AES-256 encryption standard
- Key stored in `foundations/vcf/state/credhub-key.txt`
- Persistent across configuration updates

**Generation**:
```bash
openssl rand -base64 32 > foundations/vcf/state/credhub-key.txt
chmod 600 foundations/vcf/state/credhub-key.txt
```

**Configuration**:
```yaml
.properties.credhub_key_encryption_passwords:
  value:
    - name: primary
      key:
        secret: ((credhub_encryption_key))
      primary: true
```

**Security Considerations**:
- Key stored outside git (in `state/` directory)
- File permissions restricted to owner-only (600)
- **Backup location**: `op://Private/TAS VCF Lab - Credhub Encryption Key/password`
- Backup required for disaster recovery - without this key, all CredHub credentials are unrecoverable

### 7. Resource Sizing

#### Decision: Use Small Footprint TAS
**Rationale**:
- Lab environment with limited resources
- Consolidates components onto fewer VMs
- Reduces vCPU/memory footprint by ~50%
- Still provides full TAS functionality

**Component Consolidation**:
| Small Footprint VM | Combined Components |
|--------------------|---------------------|
| Control | Cloud Controller, Cloud Controller Worker, UAA, CredHub, Routing API |
| Router | Gorouter, TCP Router, Route Syncer |
| Database | MySQL Proxy, MySQL Server |
| Compute | Diego Cell (same as standard) |

**Instance Counts**:
```yaml
resource-config:
  control:
    instances: automatic  # BOSH determines based on AZs (2)
  router:
    instances: automatic  # Minimum 2 for HA
  database:
    instances: automatic  # 1 for lab (would be 3 for prod)
  compute:
    instances: automatic  # Starts with 1, scales as needed
```

**Alternative Considered**:
- Standard TAS - Rejected due to resource constraints in lab
- Would require 20-25 VMs vs. 6-8 VMs for Small Footprint

### 8. Backup and Restore

#### Decision: Disable Automatic Backups (Lab Environment)
**Rationale**:
- Lab environment, not production
- Manual backups via BOSH Backup and Restore (BBR) if needed
- Saves storage and operational overhead

**Configuration**:
```yaml
.properties.mysql_backups: "disable"
```

**Production Consideration**:
- Enable automatic backups for production
- Configure external blobstore (S3/Azure/GCS)
- Set up BBR automation

### 9. Logging and Metrics

#### Decision: Use Default Internal Logging
**Rationale**:
- Lab environment doesn't require external log aggregation
- Logs available via `cf logs` CLI
- Metrics available in Loggregator
- Can add external syslog later if needed

**Configuration**:
```yaml
.properties.syslog_tls: "disabled"
```

**Production Consideration**:
- Enable external syslog (Splunk, ELK, etc.)
- Configure metrics forwarding (Prometheus, Datadog, etc.)
- Set up log retention policies

### 10. App Security Groups (ASGs)

#### Decision: Use Default ASGs
**Rationale**:
- Default ASGs allow outbound access to RFC1918 and internet
- Sufficient for development/lab environment
- Prevents common "app can't reach service" issues

**Default Behavior**:
- Apps can reach other apps
- Apps can reach Cloud Foundry system components
- Apps can reach internet
- Apps cannot reach link-local addresses

**Production Consideration**:
- Customize ASGs for security requirements
- Restrict egress to specific services
- Use space-scoped ASGs for multi-tenancy

### 11. Load Balancer and TLS Termination Architecture

#### Decision: TCP Passthrough with TLS Termination at Gorouter
**Rationale**:
- NSX-T load balancer configured for Layer 4 TCP passthrough (not TLS termination)
- TLS termination happens at the gorouter, not at the load balancer
- Provides flexibility for multiple certificates via Server Name Indication (SNI)
- Simplifies load balancer configuration (no certificate management at LB layer)
- Allows gorouter to see TLS SNI hostname for routing decisions

**Configuration**:

**NSX-T Load Balancer** (`terraform/nsxt/load_balancer.tf`):
```terraform
# Fast TCP Application Profile (TCP passthrough, no TLS termination)
resource "nsxt_policy_lb_fast_tcp_application_profile" "tcp_profile" {
  display_name  = "tas-tcp-profile"
  close_timeout = 8
  idle_timeout  = 1800
}

# HTTP Virtual Server (port 80)
resource "nsxt_policy_lb_virtual_server" "web_http" {
  ports                     = ["80"]
  default_pool_member_ports = ["80"]
  application_profile_path  = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  pool_path                 = nsxt_policy_lb_pool.gorouter_pool.path
}

# HTTPS Virtual Server (port 443)
resource "nsxt_policy_lb_virtual_server" "web_https" {
  ports                     = ["443"]
  default_pool_member_ports = ["443"]
  application_profile_path  = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  pool_path                 = nsxt_policy_lb_pool.gorouter_pool.path
}
```

**TAS Tile Configuration** (`foundations/vcf/config/tas.yml`):
```yaml
# TLS termination at gorouter (not load balancer)
.properties.routing_tls_termination:
  value: router

# Multiple certificates for SNI
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

# Router pool registration (HTTPS only)
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

#### Load Balancer Architecture Explanation

**Virtual Servers and Pool Members**:

| Frontend (Client) | Virtual Server | VIP:Port | Backend (Gorouter) | Pool Member | Traffic Type |
|-------------------|----------------|----------|--------------------|-------------|--------------|
| HTTP request | `tas-web-http-vs` | 31.31.10.20:80 | gorouter:80 | `10.0.2.16:80` | Plain HTTP |
| HTTPS request | `tas-web-https-vs` | 31.31.10.20:443 | gorouter:443 | `10.0.2.16:443` | Encrypted TLS |

**Why Two Virtual Servers but One Pool Member in TAS Config?**

1. **Terraform Creates Infrastructure**:
   - Two virtual servers (HTTP and HTTPS) with correct `default_pool_member_ports`
   - One pool (`tas-gorouter-pool`) that both virtual servers use
   - Virtual servers automatically route to correct backend port

2. **TAS Registers Only HTTPS**:
   - Only register port 443 in TAS tile configuration
   - HTTP virtual server still works because Terraform configured it with `default_pool_member_ports = ["80"]`
   - Don't register port 80 to avoid creating duplicate pool members

3. **Why Not Register Both Ports?**:
   - Registering both creates TWO pool members for the same VM: `VM:80` and `VM:443`
   - Load balancer round-robins between ALL members
   - HTTPS traffic could randomly go to HTTP listener → **Connection failure**
   - See: `docs/deployment-issues-resolutions.md` - "Intermittent HTTP/HTTPS Routing Failures"

**TLS Termination Flow**:

```
Client                   NSX-T LB                Gorouter                    App
======                   ========                ========                    ===
HTTPS request         →  TCP passthrough      →  TLS termination          →  HTTP
(encrypted)              (port 443)              (decrypt + route)           (plain)
                         No certificate          Multiple certs via SNI
                         inspection             Selects cert based on
                                                hostname in TLS handshake
```

**Certificate Selection via SNI**:

When a client connects to `https://app.apps.tas.vcf.lab`:

1. **TLS Handshake**: Client sends SNI hostname: `app.apps.tas.vcf.lab`
2. **Load Balancer**: Passes encrypted TLS traffic to gorouter (TCP passthrough)
3. **Gorouter**:
   - Receives TLS handshake with SNI hostname
   - Matches SNI against configured certificates:
     - System cert covers: `*.sys.tas.vcf.lab`, `*.login.sys.tas.vcf.lab`, `*.uaa.sys.tas.vcf.lab`
     - Apps cert covers: `*.apps.tas.vcf.lab`
   - Selects apps cert (matches `*.apps.tas.vcf.lab`)
   - Completes TLS handshake with client
   - Decrypts HTTPS request
   - Routes HTTP request to backend app

**Alternative Considered**:
- **TLS Termination at Load Balancer** - Rejected because:
  - Requires managing certificates at load balancer layer
  - More complex configuration (certificate uploads to NSX-T)
  - Loses SNI visibility for routing decisions
  - Can't easily support multiple certificates without additional virtual servers
  - Standard Cloud Foundry architecture uses router-level TLS termination

**Configuration Trade-offs**:

| Aspect | TCP Passthrough (Chosen) | TLS Termination at LB |
|--------|-------------------------|----------------------|
| Certificate Management | Gorouter only (via BOSH) | NSX-T + Gorouter |
| SNI Support | Native (multiple certs) | Complex (multiple VIPs or virtual servers) |
| TLS Version Control | Gorouter configuration | Load balancer configuration |
| Cipher Suite Control | Gorouter configuration | Load balancer configuration |
| TLS Offload | No (gorouter does work) | Yes (CPU savings on router VMs) |
| Routing Flexibility | Full SNI visibility | Limited (encrypted hostname) |

**Operational Benefits**:
- Simpler certificate rotation (only update gorouter certificates)
- Standard Cloud Foundry deployment pattern
- Gorouter can make intelligent routing decisions based on TLS SNI
- No load balancer reconfiguration needed for certificate changes

**Security Considerations**:
- TLS traffic encrypted from client to gorouter (end-to-end encryption)
- Load balancer can't inspect TLS traffic (no deep packet inspection)
- Certificates managed through BOSH CredHub (secure credential storage)
- Multiple certificates reduce blast radius (apps cert separate from system cert)

## Configuration Validation Strategy

### Pre-Configuration Validation
1. Verify Terraform outputs available:
   ```bash
   cd terraform/certs && terraform output
   cd terraform/nsxt && terraform output
   cd terraform/vsphere && terraform output
   ```

2. Confirm NSX-T resources exist:
   - T1 gateways: `tas-T1-Infrastructure`, `tas-T1-Deployment`, `tas-T1-Services`
   - Load balancer pools: `tas-gorouter-pool`, `tas-tcp-router-pool`, `tas-ssh-pool`
   - Segments: `tas-Infrastructure`, `tas-Deployment`, `tas-Services`

3. Verify BOSH Director deployed and healthy:
   ```bash
   om --env foundations/vcf/env/env.yml deployments
   ```

### Post-Configuration Validation
1. Check configuration applied successfully:
   ```bash
   om --env foundations/vcf/env/env.yml staged-products
   om --env foundations/vcf/env/env.yml staged-config -p srt
   ```

2. Verify pending changes ready for deployment:
   ```bash
   om --env foundations/vcf/env/env.yml pending-changes
   ```

3. Confirm no configuration errors:
   - Check Ops Manager UI for validation errors
   - Verify all required properties set
   - Ensure resource config within limits

## References

### Official Documentation
- [Configuring TAS for VMs](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/toc-tas-install-features-index.html)
- [TAS for VMs Resource Requirements](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/requirements.html) (includes Small Footprint)
- [Deploying TAS with NSX-T Networking](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/vsphere-nsx-t.html)
- [Configuring Load Balancing](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/configure-lb.html)
- [Load Balancer Health Checks](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/elastic-application-runtime/6-0/eart/configure-lb-healthcheck.html)
- [Container Security](https://techdocs.broadcom.com/us/en/vmware-tanzu/platform/tanzu-platform-for-cloud-foundry/6-0/tpcf/container-security.html)

### Project Documents
- Design: `docs/plans/2025-11-25-tas-vcf-design.md`
- Implementation: `docs/plans/2025-12-01-tas-vcf-implementation.md`
- Deployment Guide: `docs/TAS-DEPLOYMENT-GUIDE.md`
- Troubleshooting: `docs/deployment-issues-resolutions.md`

### Configuration Files
- Config Template: `foundations/vcf/config/tas.yml`
- Variables: `foundations/vcf/vars/tas.yml`
- Environment: `foundations/vcf/env/env.yml`
