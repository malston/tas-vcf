# ABOUTME: Main configuration documenting TAS VPC architecture
# ABOUTME: VPC resources managed manually via NSX UI due to limited provider support

# This module primarily serves as infrastructure-as-code documentation
# for the manually created VPC and subnets.
#
# NSX VPC support in the Terraform provider (v3.10.0) is limited:
# - No data sources for VPC or VPC subnets
# - No resources for VPC security policies
#
# Therefore, the VPC, subnets, and security policies are managed manually
# via the NSX UI, and this module documents the intended configuration.

locals {
  vpc_name = var.vpc_name
  vpc_cidr = var.vpc_private_cidr

  subnets = {
    infrastructure = {
      name = "tas-infrastructure"
      cidr = var.infrastructure_subnet_cidr
      purpose = "Ops Manager and BOSH Director"
    }
    deployment = {
      name = "tas-deployment"
      cidr = var.deployment_subnet_cidr
      purpose = "TAS Runtime VMs"
    }
    services = {
      name = "tas-services"
      cidr = var.services_subnet_cidr
      purpose = "Service Instances"
    }
  }

  external_ips = {
    ops_manager = var.ops_manager_external_ip
    web_lb      = var.web_lb_vip
    ssh_lb      = var.ssh_lb_vip
    tcp_lb      = var.tcp_lb_vip
  }
}

# Note: The following resources should be created manually via NSX UI:
#
# 1. VPC: tas-vpc (172.20.0.0/16)
#    - Centralized Connectivity Gateway enabled
#    - Edge Cluster: ec-01
#    - T0 Gateway: transit-gw
#    - External IP Block: 31.31.10.0/24
#
# 2. VPC Subnets (Private, DHCP enabled, DNS: 192.168.10.2):
#    - tas-infrastructure: 172.20.0.0/24
#    - tas-deployment: 172.20.1.0/24
#    - tas-services: 172.20.2.0/24
#
# 3. Security Policies (via NSX UI → Security → Distributed Firewall):
#    - Infrastructure: Allow SSH/HTTPS from external, full internal VPC access
#    - Deployment: Allow HTTP/HTTPS from external, full internal VPC access
#    - Services: Full internal VPC access only
#
# 4. External IP Assignments (via VM right-click → Assign External IP):
#    - Ops Manager: 31.31.10.10
#    - Web LB: 31.31.10.20
#    - SSH LB: 31.31.10.21
#    - TCP LB: 31.31.10.22
