# TAS on VCF Deployment Scripts

Automated scripts for deploying Tanzu Application Service on VMware Cloud Foundation using the `om` CLI.

## Prerequisites

- `om` CLI installed: `brew install pivotal/tap/om`
- `1Password` CLI installed: `brew install --cask 1password-cli`
- Access to Ops Manager at https://opsman.tas.vcf.lab/
- Credentials stored in 1Password

## Directory Structure

```
tas-vcf/
├── bin/                          # Executable deployment scripts
│   ├── 02-configure-director.sh  # Configures BOSH Director
│   └── 03-apply-director-changes.sh  # Deploys BOSH Director
├── foundations/vcf/              # VCF foundation configuration
│   ├── config/                   # om-compatible YAML templates
│   │   └── director.yml          # Director config with ((placeholders))
│   ├── vars/                     # Variables to interpolate
│   │   └── director.yml          # Non-sensitive values
│   └── env/                      # Environment connection details
│       └── env.yml               # Ops Manager target/auth
└── scripts/                      # Shared helper scripts
    └── configure-director.sh     # Generic director configuration logic
```

## Workflow

### 1. Configure BOSH Director

```bash
cd /Users/markalston/workspace/tas-vcf
./bin/02-configure-director.sh
```

This script:
1. Retrieves secrets from 1Password
2. Interpolates variables into `config/director.yml`
3. Calls `om configure-director` with the interpolated config
4. Configures vCenter, NSX-T, AZs, and networks

### 2. Apply Director Changes

```bash
./bin/03-apply-director-changes.sh
```

This script:
1. Runs `om pre-deploy-check` to validate configuration
2. Calls `om apply-changes` to deploy the BOSH Director
3. Takes 15-30 minutes to complete

## Configuration Details

### VPC Network Model

This deployment uses **NSX VPC** with a single subnet model:

- **VPC Subnet**: `tas-infrastructure` (172.20.0.0/24)
- **Gateway**: 172.20.0.1
- **Reserved IPs**: 172.20.0.1-172.20.0.19
- **Ops Manager**: 172.20.0.10 (internal), 31.31.0.11 (external)

**CRITICAL**: This is NOT the traditional NSX-T segment model with separate infrastructure/deployment/services networks on 10.0.x.x ranges.

### Availability Zones

- **az1**: VCF-Mgmt-Cluster / tas-az1 resource pool
- **az2**: VCF-Mgmt-Cluster / tas-az2 resource pool

### NSX Integration

- **NSX Manager**: nsx01.vcf.lab
- **Mode**: NSX-T
- **SSL Verification**: Disabled (self-signed certs)

## Manual Configuration Alternative

If you prefer manual configuration via web UI, see:
- `docs/director-configuration-guide.md` - Step-by-step web UI guide
- `/tmp/director-config-checklist.txt` - Quick reference checklist

## Verification

After deployment completes:

```bash
# SSH to Ops Manager
ssh ubuntu@opsman.tas.vcf.lab

# Test BOSH CLI
bosh env

# List deployed VMs
bosh vms
```

Expected output:
```
Instance                State    AZ   IPs
bosh/0                  running  az1  172.20.0.x
```

## Troubleshooting

### Issue: "Could not connect to Ops Manager"

- Verify Ops Manager is accessible: `curl -k https://opsman.tas.vcf.lab`
- Check network routing (see `docs/network-topology.md`)

### Issue: "NSX Manager not reachable"

- Verify NSX hostname resolves: `ping nsx01.vcf.lab`
- Check NSX credentials in 1Password

### Issue: "Resource pool not found"

Resource pools were verified during setup:
```bash
# Verify they still exist
govc pool.info /VCF-Datacenter/host/VCF-Mgmt-Cluster/Resources/tas-az1
govc pool.info /VCF-Datacenter/host/VCF-Mgmt-Cluster/Resources/tas-az2
```

## Next Steps

After BOSH Director is deployed:

1. Upload stemcells
2. Upload TAS tile
3. Configure TAS for VPC
4. Deploy TAS

## References

- [om CLI Documentation](https://github.com/pivotal-cf/om)
- [TAS on vSphere Documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Service/)
- [NSX VPC Documentation](https://docs.vmware.com/en/VMware-NSX/index.html)
