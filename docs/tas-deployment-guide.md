# TAS 6.0.6 Deployment Guide - VCF 9

## Overview

This guide covers deploying Small Footprint TAS 6.0.6 to VCF 9 using the scripted deployment approach.

## Prerequisites

✅ **Completed:**
- NSX-T networking paved (T1 gateways, segments, NAT, load balancers)
- vSphere resources created (resource pools, folders, DRS rules)
- Ops Manager deployed and configured
- BOSH Director deployed

**Required:**
- TAS 6.0.6 tile downloaded
- Ubuntu Jammy stemcell 1.990 downloaded
- DNS entries configured (*.sys.tas.vcf.lab, *.apps.tas.vcf.lab)
- Certificates generated (in terraform/certs)

## Architecture Summary

### Network Layout
| Network | CIDR | Purpose |
|---------|------|---------|
| tas-Infrastructure | 10.0.1.0/24 | Ops Manager, BOSH Director |
| tas-Deployment | 10.0.2.0/24 | TAS VMs |
| tas-Services | 10.0.3.0/24 | Service instances |

### External IPs
| Resource | IP | Purpose |
|----------|-----|---------|
| NAT Gateway | 31.31.10.1 | SNAT for all egress |
| Ops Manager | 31.31.10.10 | Management UI |
| Web LB VIP | 31.31.10.20 | HTTP/HTTPS traffic |
| SSH LB VIP | 31.31.10.21 | Diego SSH (port 2222) |
| TCP LB VIP | 31.31.10.22 | TCP Router |

### Availability Zones
| AZ | Resource Pool | Host |
|----|---------------|------|
| az1 | tas-az1 | esx02.vcf.lab |
| az2 | tas-az2 | esx03.vcf.lab |

## Deployment Steps

### 1. Upload TAS Tile

```bash
# Set tile location (if different from default)
export TAS_TILE=/path/to/srt-6.0.6-build.2.pivotal

# Upload and stage tile
bin/04-upload-tas-tile.sh
```

**What this does:**
- Uploads the 18 GB tile to Ops Manager (takes ~15-20 minutes)
- Stages the tile for configuration
- Verifies the tile is ready

### 2. Upload Stemcell

```bash
# Upload Ubuntu Jammy 1.990 stemcell
bin/05-upload-stemcell.sh
```

**Required stemcell:**
- OS: ubuntu-jammy
- Version: 1.990
- IaaS: vsphere

### 3. Configure TAS Tile

```bash
# Configure TAS with networking, certificates, NSX-T
bin/06-configure-tas.sh
```

**What this configures:**
- Domains: *.sys.tas.vcf.lab, *.apps.tas.vcf.lab
- NSX-T integration for container networking
- Load balancer pool assignments
- TLS certificates (from Terraform)
- CredHub encryption key
- Small Footprint resource sizing

### 4. Apply Changes (Deploy TAS)

```bash
# Deploy TAS to BOSH
bin/07-apply-tas-changes.sh
```

**Deployment time:** 30-60 minutes for Small Footprint

**What happens:**
- BOSH provisions VMs on deployment network
- Installs TAS components (Cloud Controller, Diego, Routers, UAA, etc.)
- Registers VMs with NSX-T load balancer pools
- Runs smoke tests and post-deploy errands

## Configuration Files

### TAS Configuration
- **Config:** `foundations/vcf/config/tas.yml`
- **Vars:** `foundations/vcf/vars/tas.yml`

### Key Configuration Sections

**Domains:**
```yaml
.cloud_controller.apps_domain: apps.tas.vcf.lab
.cloud_controller.system_domain: sys.tas.vcf.lab
```

**NSX-T Integration:**
```yaml
.properties.nsx_networking: "enable"
.properties.nsx_networking.enable.nsx_address: nsx01.vcf.lab
```

**Load Balancers:**
```yaml
resource-config:
  router:
    elb_names:
      - tas-gorouter-pool  # NSX-T pool name
```

## Post-Deployment

### Verify Deployment

```bash
# Check TAS status
source .envrc
om --env foundations/vcf/env/env.yml deployments

# Get cf admin password
om --env foundations/vcf/env/env.yml credentials \
  -p srt -c .uaa.admin_credentials -f password
```

### Login to TAS

```bash
# Target API
cf login -a https://api.sys.tas.vcf.lab --skip-ssl-validation

# Username: admin
# Password: (from om credentials command)
```

### Access Apps Manager

```
URL: https://apps.sys.tas.vcf.lab
Username: admin
Password: (from om credentials command)
```

### Deploy Test App

```bash
# Clone sample app
git clone https://github.com/cloudfoundry-samples/test-app
cd test-app

# Push app
cf push

# App will be available at: https://test-app.apps.tas.vcf.lab
```

## Troubleshooting

### Tile Upload Fails

```bash
# Check disk space on Ops Manager
ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@10.0.1.10
df -h /var/tempest/workspaces/default
```

### Configuration Fails

```bash
# Validate config file syntax
om interpolate -c foundations/vcf/config/tas.yml \
  --vars-file foundations/vcf/vars/tas.yml
```

### Deployment Fails

```bash
# Check BOSH deployment logs
ssh -i ~/.ssh/vcf_opsman_ssh_key ubuntu@10.0.1.10
bosh -e <director-name> -d srt logs
```

### NSX-T Load Balancer Issues

```bash
# Check pool members
ssh admin@nsx01.vcf.lab
get load-balancer pool tas-gorouter-pool

# Verify virtual server status
get load-balancer virtual-server
```

## Scaling

### Scale Diego Cells

```yaml
# In foundations/vcf/config/tas.yml
resource-config:
  compute:
    instances: 3  # Increase from automatic
```

Then re-run:
```bash
bin/06-configure-tas.sh
bin/07-apply-tas-changes.sh
```

### Scale Routers

```yaml
resource-config:
  router:
    instances: 2  # Increase from automatic
```

## Maintenance

### Apply Stemcell Updates

```bash
# Upload new stemcell
om --env foundations/vcf/env/env.yml upload-stemcell \
  -s light-bosh-stemcell-<version>-vsphere-esxi-ubuntu-jammy-go_agent.tgz

# Apply changes
bin/07-apply-tas-changes.sh
```

### Apply TAS Updates

```bash
# Download new tile version
# Upload using bin/04-upload-tas-tile.sh
# Configure if needed with bin/06-configure-tas.sh
# Apply changes with bin/07-apply-tas-changes.sh
```

## Reference

- [TAS Documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/concepts-overview.html)
- [NSX-T Integration](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/nsxt-index.html)
- [Small Footprint TAS](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/6.0/tas-for-vms/small-footprint.html)
