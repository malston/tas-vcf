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

3. **VMware Documentation**:
   - [TAS for VMs Documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/concepts-overview.html)
   - [NSX-T Integration Guide](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/nsxt-index.html)
   - [Small Footprint TAS Guide](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/small-footprint.html)

4. **Existing Infrastructure**:
   - Terraform outputs (`terraform/nsxt/`, `terraform/vsphere/`, `terraform/certs/`)
   - BOSH Director configuration
   - Ops Manager setup

## Configuration Decision Framework

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

#### Decision: NSX-T Policy API Mode
**Rationale**:
- Policy API is the modern NSX-T API (vs. older Manager API)
- Simpler configuration model
- Better alignment with NSX 4.0+ features
- VMware recommendation for new deployments

**Configuration**:
```yaml
.properties.nsx_networking.enable.nsx_policy_api: true
```

#### Decision: Container Network CIDR Blocks
**Rationale**:
- Need non-overlapping RFC1918 space
- `10.255.0.0/16` for Silk CNI plugin overlay
- `10.12.0.0/14` for container IP assignments (1,048,576 IPs)
- Large enough for growth but not wasteful

**Configuration**:
```yaml
.properties.nsx_networking.enable.overlay_cidr: 10.255.0.0/16
.properties.nsx_networking.enable.ip_block_cidr: 10.12.0.0/14
```

**IP Capacity Analysis**:
- /14 provides 4x /16 networks = 262,144 containers per /16
- Sufficient for 1000+ Diego cells at 250 containers each

#### Decision: NSX-T Resource Names
**Rationale**:
- Use `tas-` prefix for all NSX-T resources created by TAS
- Makes resources easy to identify and filter
- Follows naming convention established in Terraform

**Configuration**:
```yaml
.properties.nsx_networking.enable.foundation_name: tas
```

**Created Resources**:
- IP Blocks: `tas-container-ip-block`
- IP Pools: `tas-external-ip-pool`
- T0 Router: Uses existing `transit-gw`
- Logical Switches: Created per-org by TAS

### 3. Load Balancer Configuration

#### Decision: Map TAS Components to NSX-T Load Balancer Pools
**Rationale**:
- NSX-T load balancers already configured via Terraform
- Automatic registration of VMs with pools
- No manual load balancer configuration required
- High availability for all ingress points

**Configuration**:
```yaml
resource-config:
  router:
    elb_names:
      - tas-gorouter-pool    # HTTP/HTTPS traffic to apps
  tcp_router:
    elb_names:
      - tas-tcp-router-pool  # TCP routing for apps
  diego_brain:
    elb_names:
      - tas-ssh-pool         # SSH access to app containers
```

**Pool Mapping**:
| Component | Pool | VIP | Purpose |
|-----------|------|-----|---------|
| Gorouter | tas-gorouter-pool | 31.31.10.20:80,443 | HTTP/HTTPS app traffic |
| TCP Router | tas-tcp-router-pool | 31.31.10.22:1024-65535 | TCP app traffic |
| Diego Brain (SSH Proxy) | tas-ssh-pool | 31.31.10.21:2222 | SSH to containers |

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
- File permissions restricted to owner-only
- Backup required for disaster recovery

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
- [Small Footprint TAS](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/small-footprint.html)
- [NSX-T Integration](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/nsxt-index.html)
- [Load Balancer Configuration](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/configure-lb.html)
- [Security](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/security.html)

### Project Documents
- Design: `docs/plans/2025-11-25-tas-vcf-design.md`
- Implementation: `docs/plans/2025-12-01-tas-vcf-implementation.md`
- Deployment Guide: `docs/TAS-DEPLOYMENT-GUIDE.md`

### Configuration Files
- Config Template: `foundations/vcf/config/tas.yml`
- Variables: `foundations/vcf/vars/tas.yml`
- Environment: `foundations/vcf/env/env.yml`
