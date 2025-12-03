# TAS VPC Terraform Module

## Purpose

Manages TAS infrastructure using NSX VPC architecture instead of traditional T1/segment approach.

## Architecture

This module uses a **hybrid approach**:
- **Manual Creation** (NSX UI): VPC and subnets (limited Terraform provider support)
- **Terraform Management**: Security policies, references, and configuration

### Why Hybrid?

NSX VPC is relatively new (introduced in VCF 9) and the Terraform provider has limited support for VPC resources. We create the VPC and subnets manually via NSX UI, then use Terraform to:
- Reference the manually created resources via data sources
- Manage security policies
- Export paths and IDs for other modules
- Document the intended configuration as code

## Prerequisites

### Manual Steps (NSX UI)

1. **Create VPC**: `tas-vpc` with private CIDR `172.20.0.0/16`
   - Enable "Centralized Connectivity Gateway"
   - Connect to T0 gateway `transit-gw`
   - Assign external IP block `31.31.10.0/24`

2. **Create Subnets** in `tas-vpc`:
   - `tas-infrastructure`: 172.20.0.0/24 (Ops Manager, BOSH)
   - `tas-deployment`: 172.20.1.0/24 (TAS Runtime VMs)
   - `tas-services`: 172.20.2.0/24 (Service Instances)
   - All subnets: Private type, DHCP enabled, DNS: 192.168.10.2

See detailed instructions: `docs/plans/2025-12-03-tas-vpc-migration-plan.md`

## Usage

### 1. Set NSX Credentials

```bash
cd terraform/vpc
export TF_VAR_nsxt_password=$(op read "op://Private/nsx01.vcf.lab/password")
```

### 2. Copy and Customize Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (defaults should work)
```

### 3. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify Outputs

```bash
terraform output
```

You should see:
- VPC ID and path
- Subnet IDs and paths for all three subnets
- External IP assignments

## What This Module Manages

### ✅ Currently Managed
- **Security Policies**: Distributed firewall rules for all three subnets
- **Data Sources**: References to manually created VPC and subnets
- **Outputs**: Exports paths/IDs for use by other modules

### ❌ Not Yet Managed (Manual via NSX UI)
- VPC creation and configuration
- Subnet creation and DHCP settings
- External IP assignments (use "Assign External IP" in NSX UI)
- Load balancer configuration

## External IP Assignments

After creating the VPC and subnets, assign external IPs manually:

1. Deploy VM to subnet (Ops Manager, load balancer, etc.)
2. Right-click VM in NSX UI → "Assign External IP"
3. Select IP from VPC External IP Block

External IPs defined in this module:
- Ops Manager: `31.31.10.10`
- Web LB: `31.31.10.20`
- SSH LB: `31.31.10.21`
- TCP LB: `31.31.10.22`

## Security Policies

This module creates distributed firewall policies for each subnet:

### Infrastructure Subnet
- Allow SSH (port 22) from external
- Allow HTTPS (port 443) from external
- Allow all traffic within VPC
- Allow outbound internet access

### Deployment Subnet
- Allow HTTP/HTTPS from external
- Allow all traffic within VPC
- Allow outbound internet access

### Services Subnet
- Allow all traffic within VPC
- Allow outbound internet access

## Outputs

```hcl
vpc_id                    # VPC resource ID
vpc_path                  # VPC policy path
infrastructure_subnet_id  # Infrastructure subnet ID
infrastructure_subnet_path # Infrastructure subnet policy path
deployment_subnet_id      # Deployment subnet ID
deployment_subnet_path    # Deployment subnet policy path
services_subnet_id        # Services subnet ID
services_subnet_path      # Services subnet policy path
ops_manager_external_ip   # 31.31.10.10
web_lb_vip               # 31.31.10.20
ssh_lb_vip               # 31.31.10.21
tcp_lb_vip               # 31.31.10.22
```

## Troubleshooting

### Error: VPC not found

Ensure you've created the VPC manually via NSX UI with the exact name `tas-vpc` (or update `var.vpc_name`).

### Error: Subnet not found

Ensure all three subnets are created with exact names:
- `tas-infrastructure`
- `tas-deployment`
- `tas-services`

### Security policies not applying

Wait a few minutes for NSX to realize the distributed firewall rules. Check NSX UI under Security → Distributed Firewall.

## References

- [William Lam's VPC Guide](https://williamlam.com/2025/07/ms-a2-vcf-9-0-lab-configuring-nsx-virtual-private-cloud-vpc.html)
- [TAS VPC Migration Plan](../../docs/plans/2025-12-03-tas-vpc-migration-plan.md)
- [NSX-T Terraform Provider Docs](https://registry.terraform.io/providers/vmware/nsxt/latest/docs)
