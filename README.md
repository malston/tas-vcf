# TAS 6.0.6 on VCF 9

Deploy Tanzu Application Service 6.0.6 to VCF 9 homelab environment.

## Prerequisites

- VCF 9 environment with NSX-T
- Terraform >= 1.5.0
- Platform Automation Toolkit 5.x
- Concourse (existing instance in tanzu-homelab)

## Quick Start

### 1. Pave NSX-T

```bash
cd terraform/nsxt
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### 2. Pave vSphere

```bash
cd terraform/vsphere
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### 3. Generate Certificates

```bash
cd terraform/certs
terraform init
terraform apply
```

### 4. Configure DNS

```bash
./scripts/setup-dns.sh
```

### 5. Deploy TAS

Set the Platform Automation pipeline in Concourse targeting this foundation.

## Architecture

See [Design Document](docs/plans/2025-11-25-tas-vcf-design.md) for full details.

### Network Layout

| Network | CIDR | Gateway | Purpose |
|---------|------|---------|---------|
| Infrastructure | 10.0.1.0/24 | 10.0.1.1 | Ops Manager, BOSH |
| Deployment | 10.0.2.0/24 | 10.0.2.1 | TAS VMs |
| Services | 10.0.3.0/24 | 10.0.3.1 | Service instances |

### External IPs

| Resource | IP |
|----------|-----|
| NAT Gateway | 31.31.10.1 |
| Ops Manager | 31.31.10.10 |
| Web LB VIP | 31.31.10.20 |
| SSH LB VIP | 31.31.10.21 |
| TCP LB VIP | 31.31.10.22 |

### Availability Zones

| AZ | Resource Pool | Host |
|----|---------------|------|
| az1 | tas-az1 | esx02.vcf.lab |
| az2 | tas-az2 | esx03.vcf.lab |

## Directory Structure

```
tas-vcf/
├── terraform/
│   ├── nsxt/          # NSX-T paving
│   ├── vsphere/       # vSphere resources
│   └── certs/         # Certificate generation
├── foundations/
│   └── vcf/           # Platform Automation config
├── pipelines/         # Concourse pipelines
├── scripts/           # Helper scripts
└── docs/              # Documentation
```
