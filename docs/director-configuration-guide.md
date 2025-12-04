# BOSH Director Configuration Guide for VPC Deployment

## Overview

This guide provides step-by-step instructions for configuring the BOSH Director in Ops Manager for the VPC deployment at <https://opsman.tas.vcf.lab/>

**Authentication**:

- Username: `admin`
- Password: `op read op://Private/opsman.tas.vcf.lab/password`

---

## 1. vCenter Config

Navigate to: **BOSH Director for vSphere** → **vCenter Config**

### Settings

| Field | Value | Notes |
|-------|-------|-------|
| **vCenter Host** | `vc01.vcf.lab` | |
| **vCenter Username** | `administrator@vsphere.local` | |
| **vCenter Password** | *from 1Password* | `op://Private/vc01.vcf.lab/password` |
| **Datacenter Name** | `VCF-Datacenter` | |
| **Virtual Disk Type** | `thin` | Recommended for vSAN |
| **Ephemeral Datastore Names** | `vsanDatastore` | |
| **Persistent Datastore Names** | `vsanDatastore` | |

### Advanced Settings

| Field | Value |
|-------|-------|
| **VM Folder** | `tas/vms` |
| **Template Folder** | `tas/templates` |
| **Disk path Folder** | `tas/disks` |

### NSX Networking Settings

| Field | Value | Notes |
|-------|-------|-------|
| **NSX Mode** | `NSX-T` | ✓ Check the box |
| **NSX Address** | `nsx01.vcf.lab` | NSX Manager hostname |
| **NSX Username** | `admin` | |
| **NSX Password** | *from 1Password* | `op://Private/nsx01.vcf.lab/password` |
| **NSX CA Cert** | *(Leave empty)* | Self-signed cert |

**⚠️ IMPORTANT**: Uncheck "**Enable SSL verification**" for lab environment

**Click**: "Save" at the bottom of the page

---

## 2. Director Config

Navigate to: **BOSH Director for vSphere** → **Director Config**

### Settings

| Field | Value | Notes |
|-------|-------|-------|
| **NTP Servers** | `pool.ntp.org` | Or your preferred NTP server |
| **Enable VM Resurrector Plugin** | ✓ Checked | Auto-recovery of failed VMs |
| **Enable Post Deploy Scripts** | ✓ Checked | |
| **Recreate all VMs** | ☐ Unchecked | Only for updates |
| **Recreate all Persistent Disks** | ☐ Unchecked | |
| **Enable bosh deploy retries** | ✓ Checked | Retry failed deployments |

### Database Location

- **Internal Database** (default) - Use this for lab

### Blobstore Location

- **Internal** (default) - Use this for lab

**Click**: "Save"

---

## 3. Create Availability Zones

Navigate to: **BOSH Director for vSphere** → **Create Availability Zones**

### AZ 1

| Field | Value |
|-------|-------|
| **Name** | `az1` |
| **IaaS Configuration** | *(auto-selected)* |
| **Clusters** | |
| - **Cluster** | `VCF-Mgmt-Cluster` |
| - **Resource Pool** | `tas-az1` |
| - **Host Group** | *(leave empty)* |

**Click**: "+ Add Cluster" if you need multiple clusters (optional for lab)

### AZ 2

Click "**Add**" to create a second AZ:

| Field | Value |
|-------|-------|
| **Name** | `az2` |
| **IaaS Configuration** | *(auto-selected)* |
| **Clusters** | |
| - **Cluster** | `VCF-Mgmt-Cluster` |
| - **Resource Pool** | `tas-az2` |
| - **Host Group** | *(leave empty)* |

**✅ VERIFIED**: Resource pools `tas-az1` and `tas-az2` exist in vCenter.

**Click**: "Save"

---

## 4. Create Networks

Navigate to: **BOSH Director for vSphere** → **Create Networks**

### ⚠️ CRITICAL: VPC Network Configuration

Your deployment uses **NSX VPC** with the subnet `tas-infrastructure` (172.20.0.0/24). The traditional NSX-T segments (10.0.x.x) are NOT being used.

### Network: infrastructure

| Field | Value | Notes |
|-------|-------|-------|
| **Name** | `infrastructure` | |
| **vSphere Network Name** | `tas-infrastructure` | ⚠️ This is the VPC subnet name |
| **CIDR** | `172.20.0.0/24` | VPC subnet CIDR |
| **Reserved IP Ranges** | `172.20.0.1-172.20.0.19` | Reserved: gateway + Ops Manager |
| **DNS** | `192.168.10.2` | Your DNS server |
| **Gateway** | `172.20.0.1` | VPC subnet gateway |
| **Availability Zones** | `az1`, `az2` | Both AZs |

**⚠️ DO NOT ADD** deployment or services networks yet - VPC uses a single subnet model initially.

**Click**: "Save"

---

## 5. Assign AZs and Networks

Navigate to: **BOSH Director for vSphere** → **Assign AZs and Networks**

### Settings

| Field | Value |
|-------|-------|
| **Singleton Availability Zone** | `az1` |
| **Network** | `infrastructure` |

**Click**: "Save"

---

## 6. Security

Navigate to: **BOSH Director for vSphere** → **Security**

### Settings

| Field | Value | Notes |
|-------|-------|-------|
| **Trusted Certificates** | *(leave empty for lab)* | Add if using internal CA |
| **VM Password Type** | `Generate passwords` | Recommended |

**Click**: "Save"

---

## 7. BOSH DNS Config

Navigate to: **BOSH Director for vSphere** → **BOSH DNS Config**

### Settings

Leave all fields as default (no custom DNS configuration needed for lab)

**Click**: "Save"

---

## 8. Syslog

Navigate to: **BOSH Director for vSphere** → **Syslog**

### Settings

Leave unconfigured (optional for lab)

**Click**: "Save"

---

## 9. Resource Config

Navigate to: **BOSH Director for vSphere** → **Resource Config**

### Settings

Review the default resource allocations:

| Job | Instances | VM Type | Persistent Disk |
|-----|-----------|---------|-----------------|
| **BOSH Director** | 1 | Automatic | 50 GB |
| **Master Compilation Job** | 1 | Automatic | - |

**For Lab**: Keep defaults

**For Production**: Increase based on workload

**Click**: "Save"

---

## 10. Review Pending Changes

Navigate to: **Review Pending Changes** (top menu)

### Pre-Deployment Checklist

- ✅ vCenter credentials configured
- ✅ NSX-T integration enabled
- ✅ Availability zones created (`az1`, `az2`)
- ✅ Resource pools exist in vCenter (`tas-az1`, `tas-az2`)
- ✅ Network `infrastructure` configured with VPC subnet
- ✅ All configurations saved

### Deploy

1. Check: ✓ **BOSH Director**
2. Click: "**Apply Changes**"

---

## Deployment Monitoring

The deployment will take **15-30 minutes**. Monitor progress:

1. **Installation Dashboard**: Shows overall progress
2. **Change Log**: Click "**Logs**" to view detailed output
3. **BOSH Director Logs**: Available after deployment

### Expected Steps

1. Creating infrastructure
2. Compiling packages
3. Creating VMs
4. Running post-deploy scripts
5. Finalizing deployment

---

## Verification After Deployment

### 1. Check BOSH Director Status

Navigate to: **BOSH Director for vSphere** tile

Status should show: ✅ **Installed**

### 2. SSH to Ops Manager

```bash
ssh ubuntu@opsman.tas.vcf.lab
# or
ssh ubuntu@31.31.0.11
```

### 3. Authenticate with BOSH

```bash
# Get BOSH credentials from Ops Manager
export BOSH_CLIENT=ops_manager
export BOSH_CLIENT_SECRET=$(om credentials \
  -p bosh \
  -c .opsmanager.bosh-admin-credentials.password)
export BOSH_ENVIRONMENT=172.20.0.10  # Ops Manager IP
export BOSH_CA_CERT=/var/tempest/workspaces/default/root_ca_certificate

# Test BOSH connection
bosh env
```

### 4. Verify VMs

```bash
bosh vms
```

Expected output:

```
Instance                                     State    AZ   IPs
bosh/0                                       running  az1  172.20.0.x
```

---

## Troubleshooting

### Issue: "Could not connect to vCenter"

- Verify vCenter hostname resolves: `ping vc01.vcf.lab`
- Check credentials in 1Password
- Verify Ops Manager can reach vCenter: `ssh ubuntu@opsman.tas.vcf.lab`, then `curl -k https://vc01.vcf.lab`

### Issue: "NSX Manager not reachable"

- Verify NSX hostname resolves: `ping nsx01.vcf.lab`
- Check NSX Manager is up: `ssh ubuntu@opsman.tas.vcf.lab`, then `curl -k https://nsx01.vcf.lab`

### Issue: "Resource pool not found"

- Verify resource pools exist in vCenter:

  ```bash
  govc pool.info /VCF-Datacenter/host/VCF-Mgmt-Cluster/Resources/tas-az1
  govc pool.info /VCF-Datacenter/host/VCF-Mgmt-Cluster/Resources/tas-az2
  ```

### Issue: "Network 'tas-infrastructure' not found"

- Verify VPC subnet exists in NSX:

  ```bash
  # SSH to NSX Manager
  get logical-switch tas-infrastructure
  ```

### Issue: Deployment fails during compilation

- Check internet connectivity from Ops Manager
- Verify DNS resolution: `nslookup pool.ntp.org`
- Check NTP: `sudo ntpq -p`

---

## Next Steps After Director Deployment

1. **Upload Stemcells**: Download and upload Ubuntu Jammy stemcell for vSphere
2. **Install TAS**: Upload TAS tile and configure
3. **Configure Load Balancers**: Set up NSX load balancers for TAS
4. **Configure DNS**: Add wildcard DNS for apps domain

---

## Reference Documentation

- [Ops Manager API](https://docs.pivotal.io/platform/opsman-api/)
- [BOSH CLI](https://bosh.io/docs/cli-v2/)
- [TAS on vSphere](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/)
- [NSX VPC Configuration](https://docs.vmware.com/en/VMware-NSX/index.html)

---

## Important Notes

### VPC vs Traditional NSX-T Networks

Your deployment uses **VPC subnet model**:

- Single subnet: `tas-infrastructure` (172.20.0.0/24)
- External IP auto-assignment via VPC
- Simplified routing through VPC gateway

**Traditional NSX-T model** (NOT used):

- Separate segments: tas-Infrastructure, tas-Deployment, tas-Services
- Manual NAT configuration
- T1 gateway per segment

### Network Configuration Gotcha

⚠️ **Do NOT configure networks that don't exist**. The director config templates reference traditional NSX-T segments (`tas-Infrastructure`, `tas-Deployment`, `tas-Services` on 10.0.x.x networks) that are NOT present in your VPC deployment.

Only configure what actually exists:

- ✅ `tas-infrastructure` VPC subnet (172.20.0.0/24)
- ❌ NOT tas-Infrastructure segment (10.0.1.0/24)
- ❌ NOT tas-Deployment segment (10.0.2.0/24)
- ❌ NOT tas-Services segment (10.0.3.0/24)
