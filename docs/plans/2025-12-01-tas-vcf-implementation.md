# TAS 6.0.6 on VCF 9 - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy TAS 6.0.6 to VCF 9 homelab using Terraform for IaaS paving and Platform Automation Toolkit for TAS deployment.

**Architecture:** Traditional NSX-T topology (T0→T1→Segment) with Terraform modules for NSX-T networking, vSphere resources, and certificate generation. Platform Automation configs drive Ops Manager and TAS deployment via existing Concourse.

**Tech Stack:** Terraform (NSX-T provider ~3.x, vSphere provider ~2.x, TLS provider ~4.x), Platform Automation Toolkit 5.x, Concourse

---

## Phase 1: Project Setup

### Task 1: Initialize Terraform Structure

**Files:**
- Create: `terraform/nsxt/versions.tf`
- Create: `terraform/nsxt/provider.tf`
- Create: `terraform/nsxt/variables.tf`
- Create: `terraform/vsphere/versions.tf`
- Create: `terraform/vsphere/provider.tf`
- Create: `terraform/vsphere/variables.tf`
- Create: `terraform/certs/versions.tf`
- Create: `terraform/certs/variables.tf`

**Step 1: Create NSX-T module versions.tf**

```hcl
# terraform/nsxt/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    nsxt = {
      source  = "vmware/nsxt"
      version = "~> 3.4"
    }
  }
}
```

**Step 2: Create NSX-T provider.tf**

```hcl
# terraform/nsxt/provider.tf
provider "nsxt" {
  host                 = var.nsxt_host
  username             = var.nsxt_username
  password             = var.nsxt_password
  allow_unverified_ssl = var.allow_unverified_ssl
}
```

**Step 3: Create NSX-T variables.tf**

```hcl
# terraform/nsxt/variables.tf
variable "nsxt_host" {
  description = "NSX Manager hostname or IP"
  type        = string
  default     = "nsx01.vcf.lab"
}

variable "nsxt_username" {
  description = "NSX Manager username"
  type        = string
  default     = "admin"
}

variable "nsxt_password" {
  description = "NSX Manager password"
  type        = string
  sensitive   = true
}

variable "allow_unverified_ssl" {
  description = "Allow self-signed certificates"
  type        = bool
  default     = true
}

variable "environment_name" {
  description = "Environment identifier for resource naming"
  type        = string
  default     = "tas"
}

variable "edge_cluster_name" {
  description = "Name of the NSX Edge Cluster"
  type        = string
  default     = "edge-cluster-01"
}

variable "transport_zone_name" {
  description = "Name of the overlay transport zone"
  type        = string
  default     = "overlay-tz"
}

variable "t0_gateway_name" {
  description = "Name of the existing T0 gateway"
  type        = string
  default     = "T0-Gateway"
}

# Network CIDRs
variable "infrastructure_cidr" {
  description = "CIDR for infrastructure network"
  type        = string
  default     = "10.0.1.0/24"
}

variable "deployment_cidr" {
  description = "CIDR for deployment network"
  type        = string
  default     = "10.0.2.0/24"
}

variable "services_cidr" {
  description = "CIDR for services network"
  type        = string
  default     = "10.0.3.0/24"
}

# External IPs
variable "nat_gateway_ip" {
  description = "SNAT IP for all TAS egress"
  type        = string
  default     = "31.31.10.1"
}

variable "ops_manager_external_ip" {
  description = "External IP for Ops Manager"
  type        = string
  default     = "31.31.10.10"
}

variable "ops_manager_internal_ip" {
  description = "Internal IP for Ops Manager"
  type        = string
  default     = "10.0.1.10"
}

variable "web_lb_vip" {
  description = "VIP for web (HTTP/HTTPS) load balancer"
  type        = string
  default     = "31.31.10.20"
}

variable "ssh_lb_vip" {
  description = "VIP for SSH load balancer"
  type        = string
  default     = "31.31.10.21"
}

variable "tcp_lb_vip" {
  description = "VIP for TCP router load balancer"
  type        = string
  default     = "31.31.10.22"
}

# Container networking
variable "external_ip_pool_start" {
  description = "Start of external IP pool for container networking"
  type        = string
  default     = "31.31.10.100"
}

variable "external_ip_pool_end" {
  description = "End of external IP pool for container networking"
  type        = string
  default     = "31.31.10.200"
}

variable "container_ip_block_cidr" {
  description = "CIDR for container-to-container networking"
  type        = string
  default     = "10.12.0.0/14"
}
```

**Step 4: Create vSphere module versions.tf**

```hcl
# terraform/vsphere/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}
```

**Step 5: Create vSphere provider.tf**

```hcl
# terraform/vsphere/provider.tf
provider "vsphere" {
  vsphere_server       = var.vcenter_host
  user                 = var.vcenter_username
  password             = var.vcenter_password
  allow_unverified_ssl = var.allow_unverified_ssl
}
```

**Step 6: Create vSphere variables.tf**

```hcl
# terraform/vsphere/variables.tf
variable "vcenter_host" {
  description = "vCenter hostname or IP"
  type        = string
  default     = "vc01.vcf.lab"
}

variable "vcenter_username" {
  description = "vCenter username"
  type        = string
  default     = "administrator@vsphere.local"
}

variable "vcenter_password" {
  description = "vCenter password"
  type        = string
  sensitive   = true
}

variable "allow_unverified_ssl" {
  description = "Allow self-signed certificates"
  type        = bool
  default     = true
}

variable "datacenter_name" {
  description = "vSphere datacenter name"
  type        = string
  default     = "VCF-DC"
}

variable "cluster_name" {
  description = "vSphere cluster name"
  type        = string
  default     = "VCF-Mgmt-Cluster"
}

variable "datastore_name" {
  description = "vSAN datastore name"
  type        = string
  default     = "vsan-ds"
}

variable "environment_name" {
  description = "Environment identifier for resource naming"
  type        = string
  default     = "tas"
}

# Host names for DRS rules
variable "infrastructure_host" {
  description = "ESXi host for infrastructure VMs"
  type        = string
  default     = "esx01.vcf.lab"
}

variable "az1_host" {
  description = "ESXi host for AZ1 VMs"
  type        = string
  default     = "esx02.vcf.lab"
}

variable "az2_host" {
  description = "ESXi host for AZ2 VMs"
  type        = string
  default     = "esx03.vcf.lab"
}
```

**Step 7: Create certs module versions.tf**

```hcl
# terraform/certs/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
```

**Step 8: Create certs variables.tf**

```hcl
# terraform/certs/variables.tf
variable "base_domain" {
  description = "Base domain for TAS"
  type        = string
  default     = "tas.vcf.lab"
}

variable "organization" {
  description = "Organization name for certificates"
  type        = string
  default     = "Homelab"
}

variable "validity_period_hours" {
  description = "Certificate validity in hours (default 1 year)"
  type        = number
  default     = 8760
}

variable "output_path" {
  description = "Path to write certificate files"
  type        = string
  default     = "./generated"
}
```

**Step 9: Commit**

```bash
git add terraform/
git commit -m "feat: add Terraform module structure with provider configs"
```

---

## Phase 2: NSX-T Paving

### Task 2: Create NSX-T Data Sources

**Files:**
- Create: `terraform/nsxt/data.tf`

**Step 1: Create data sources file**

```hcl
# terraform/nsxt/data.tf
data "nsxt_policy_edge_cluster" "edge_cluster" {
  display_name = var.edge_cluster_name
}

data "nsxt_policy_transport_zone" "overlay_tz" {
  display_name = var.transport_zone_name
}

data "nsxt_policy_tier0_gateway" "t0_gateway" {
  display_name = var.t0_gateway_name
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/data.tf
git commit -m "feat(nsxt): add data sources for edge cluster, transport zone, T0"
```

---

### Task 3: Create T1 Gateways

**Files:**
- Create: `terraform/nsxt/t1_gateways.tf`

**Step 1: Create T1 gateways**

```hcl
# terraform/nsxt/t1_gateways.tf

# T1 Gateway for Infrastructure (Ops Manager, BOSH Director)
resource "nsxt_policy_tier1_gateway" "t1_infrastructure" {
  display_name              = "${var.environment_name}-T1-Infrastructure"
  description               = "T1 Gateway for TAS Infrastructure components"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = true
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT", "TIER1_LB_VIP", "TIER1_LB_SNAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# T1 Gateway for Deployment (Diego cells, Routers, UAA, etc.)
resource "nsxt_policy_tier1_gateway" "t1_deployment" {
  display_name              = "${var.environment_name}-T1-Deployment"
  description               = "T1 Gateway for TAS Deployment components"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "NON_PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = true
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT", "TIER1_LB_VIP", "TIER1_LB_SNAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# T1 Gateway for Services (on-demand service instances)
resource "nsxt_policy_tier1_gateway" "t1_services" {
  display_name              = "${var.environment_name}-T1-Services"
  description               = "T1 Gateway for TAS Services"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "NON_PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = true
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/t1_gateways.tf
git commit -m "feat(nsxt): add T1 gateways for infrastructure, deployment, services"
```

---

### Task 4: Create Segments

**Files:**
- Create: `terraform/nsxt/segments.tf`

**Step 1: Create segments**

```hcl
# terraform/nsxt/segments.tf

# Infrastructure segment (Ops Manager, BOSH Director)
resource "nsxt_policy_segment" "infrastructure" {
  display_name        = "${var.environment_name}-Infrastructure"
  description         = "Segment for TAS Infrastructure components"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_infrastructure.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.infrastructure_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# Deployment segment (Diego cells, Routers, UAA, etc.)
resource "nsxt_policy_segment" "deployment" {
  display_name        = "${var.environment_name}-Deployment"
  description         = "Segment for TAS Deployment components"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_deployment.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.deployment_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# Services segment (on-demand service instances)
resource "nsxt_policy_segment" "services" {
  display_name        = "${var.environment_name}-Services"
  description         = "Segment for TAS Services"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_services.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.services_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/segments.tf
git commit -m "feat(nsxt): add segments for infrastructure, deployment, services"
```

---

### Task 5: Create NAT Rules

**Files:**
- Create: `terraform/nsxt/nat.tf`

**Step 1: Create NAT rules on T0**

```hcl
# terraform/nsxt/nat.tf

# SNAT rule for all TAS VMs (egress)
resource "nsxt_policy_nat_rule" "snat_all" {
  display_name         = "${var.environment_name}-SNAT-All"
  description          = "SNAT for all TAS VM egress traffic"
  action               = "SNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  source_networks      = ["10.0.0.0/16"]
  translated_networks  = [var.nat_gateway_ip]
  logging              = false
  firewall_match       = "MATCH_INTERNAL_ADDRESS"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# SNAT rule for Ops Manager (specific source IP)
resource "nsxt_policy_nat_rule" "snat_ops_manager" {
  display_name         = "${var.environment_name}-SNAT-OpsManager"
  description          = "SNAT for Ops Manager egress traffic"
  action               = "SNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  source_networks      = [var.ops_manager_internal_ip]
  translated_networks  = [var.ops_manager_external_ip]
  logging              = false
  firewall_match       = "MATCH_INTERNAL_ADDRESS"
  sequence_number      = 10

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# DNAT rule for Ops Manager (inbound access)
resource "nsxt_policy_nat_rule" "dnat_ops_manager" {
  display_name         = "${var.environment_name}-DNAT-OpsManager"
  description          = "DNAT for Ops Manager inbound traffic"
  action               = "DNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  destination_networks = [var.ops_manager_external_ip]
  translated_networks  = [var.ops_manager_internal_ip]
  logging              = false
  firewall_match       = "MATCH_EXTERNAL_ADDRESS"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/nat.tf
git commit -m "feat(nsxt): add NAT rules for TAS egress and Ops Manager access"
```

---

### Task 6: Create IP Pools and Blocks

**Files:**
- Create: `terraform/nsxt/ip_pools.tf`

**Step 1: Create IP pool and block for container networking**

```hcl
# terraform/nsxt/ip_pools.tf

# External IP Pool for container networking (per-org NAT)
resource "nsxt_policy_ip_pool" "external_ip_pool" {
  display_name = "${var.environment_name}-external-ip-pool"
  description  = "External IP pool for TAS container networking"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_ip_pool_static_subnet" "external_ip_pool_subnet" {
  display_name = "${var.environment_name}-external-ip-pool-subnet"
  pool_path    = nsxt_policy_ip_pool.external_ip_pool.path
  cidr         = "31.31.10.0/24"
  gateway      = "31.31.10.1"

  allocation_range {
    start = var.external_ip_pool_start
    end   = var.external_ip_pool_end
  }
}

# IP Block for container-to-container networking
resource "nsxt_policy_ip_block" "container_ip_block" {
  display_name = "${var.environment_name}-container-ip-block"
  description  = "IP block for TAS container-to-container networking"
  cidr         = var.container_ip_block_cidr

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/ip_pools.tf
git commit -m "feat(nsxt): add IP pool and block for container networking"
```

---

### Task 7: Create Load Balancer Components

**Files:**
- Create: `terraform/nsxt/load_balancer.tf`

**Step 1: Create load balancer service, monitors, pools, and virtual servers**

```hcl
# terraform/nsxt/load_balancer.tf

# --- Health Monitors ---

resource "nsxt_policy_lb_http_monitor_profile" "gorouter_monitor" {
  display_name       = "${var.environment_name}-gorouter-monitor"
  description        = "Health monitor for GoRouters"
  request_method     = "GET"
  request_url        = "/health"
  request_version    = "HTTP_VERSION_1_1"
  response_status_codes = [200]
  monitor_port       = 8080
  request_header {
    name  = "Host"
    value = "gorouter-health"
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_http_monitor_profile" "tcp_router_monitor" {
  display_name       = "${var.environment_name}-tcp-router-monitor"
  description        = "Health monitor for TCP Routers"
  request_method     = "GET"
  request_url        = "/health"
  request_version    = "HTTP_VERSION_1_1"
  response_status_codes = [200]
  monitor_port       = 80

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_tcp_monitor_profile" "ssh_monitor" {
  display_name = "${var.environment_name}-ssh-monitor"
  description  = "Health monitor for Diego Brain SSH"
  monitor_port = 2222

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Server Pools ---

resource "nsxt_policy_lb_pool" "gorouter_pool" {
  display_name         = "${var.environment_name}-gorouter-pool"
  description          = "Pool for GoRouter instances"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_http_monitor_profile.gorouter_monitor.path
  snat_translation {
    type = "AUTOMAP"
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_pool" "tcp_router_pool" {
  display_name         = "${var.environment_name}-tcp-router-pool"
  description          = "Pool for TCP Router instances"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_http_monitor_profile.tcp_router_monitor.path
  snat_translation {
    type = "TRANSPARENT"
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_pool" "ssh_pool" {
  display_name         = "${var.environment_name}-ssh-pool"
  description          = "Pool for Diego Brain SSH"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_tcp_monitor_profile.ssh_monitor.path
  snat_translation {
    type = "TRANSPARENT"
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Application Profiles ---

resource "nsxt_policy_lb_fast_tcp_application_profile" "tcp_profile" {
  display_name  = "${var.environment_name}-tcp-profile"
  description   = "TCP application profile for TAS"
  close_timeout = 8
  idle_timeout  = 1800

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Virtual Servers ---

resource "nsxt_policy_lb_virtual_server" "web_http" {
  display_name               = "${var.environment_name}-web-http-vs"
  description                = "Virtual server for HTTP traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.web_lb_vip
  ports                      = ["80"]
  default_pool_member_ports  = ["80"]
  pool_path                  = nsxt_policy_lb_pool.gorouter_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "web_https" {
  display_name               = "${var.environment_name}-web-https-vs"
  description                = "Virtual server for HTTPS traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.web_lb_vip
  ports                      = ["443"]
  default_pool_member_ports  = ["443"]
  pool_path                  = nsxt_policy_lb_pool.gorouter_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "ssh" {
  display_name               = "${var.environment_name}-ssh-vs"
  description                = "Virtual server for SSH traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.ssh_lb_vip
  ports                      = ["2222"]
  default_pool_member_ports  = ["2222"]
  pool_path                  = nsxt_policy_lb_pool.ssh_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "tcp_router" {
  display_name               = "${var.environment_name}-tcp-router-vs"
  description                = "Virtual server for TCP router traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.tcp_lb_vip
  ports                      = ["1024-65535"]
  default_pool_member_ports  = ["1024-65535"]
  pool_path                  = nsxt_policy_lb_pool.tcp_router_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Load Balancer Service ---

resource "nsxt_policy_lb_service" "tas_lb" {
  display_name      = "${var.environment_name}-lb-service"
  description       = "Load balancer service for TAS"
  connectivity_path = nsxt_policy_tier1_gateway.t1_deployment.path
  size              = "SMALL"
  enabled           = true

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/load_balancer.tf
git commit -m "feat(nsxt): add load balancer service, pools, monitors, virtual servers"
```

---

### Task 8: Create NSX-T Outputs

**Files:**
- Create: `terraform/nsxt/outputs.tf`

**Step 1: Create outputs**

```hcl
# terraform/nsxt/outputs.tf

# T1 Gateway outputs
output "t1_infrastructure_path" {
  description = "Path of T1 Infrastructure gateway"
  value       = nsxt_policy_tier1_gateway.t1_infrastructure.path
}

output "t1_deployment_path" {
  description = "Path of T1 Deployment gateway"
  value       = nsxt_policy_tier1_gateway.t1_deployment.path
}

output "t1_services_path" {
  description = "Path of T1 Services gateway"
  value       = nsxt_policy_tier1_gateway.t1_services.path
}

# Segment outputs
output "infrastructure_segment_name" {
  description = "Name of infrastructure segment"
  value       = nsxt_policy_segment.infrastructure.display_name
}

output "deployment_segment_name" {
  description = "Name of deployment segment"
  value       = nsxt_policy_segment.deployment.display_name
}

output "services_segment_name" {
  description = "Name of services segment"
  value       = nsxt_policy_segment.services.display_name
}

# Load balancer pool names (for BOSH/TAS configuration)
output "gorouter_pool_name" {
  description = "Name of GoRouter LB pool"
  value       = nsxt_policy_lb_pool.gorouter_pool.display_name
}

output "tcp_router_pool_name" {
  description = "Name of TCP Router LB pool"
  value       = nsxt_policy_lb_pool.tcp_router_pool.display_name
}

output "ssh_pool_name" {
  description = "Name of SSH LB pool"
  value       = nsxt_policy_lb_pool.ssh_pool.display_name
}

# IP pool and block outputs
output "external_ip_pool_name" {
  description = "Name of external IP pool"
  value       = nsxt_policy_ip_pool.external_ip_pool.display_name
}

output "container_ip_block_name" {
  description = "Name of container IP block"
  value       = nsxt_policy_ip_block.container_ip_block.display_name
}

# VIP outputs
output "web_lb_vip" {
  description = "VIP for web load balancer"
  value       = var.web_lb_vip
}

output "ssh_lb_vip" {
  description = "VIP for SSH load balancer"
  value       = var.ssh_lb_vip
}

output "tcp_lb_vip" {
  description = "VIP for TCP router load balancer"
  value       = var.tcp_lb_vip
}

output "ops_manager_external_ip" {
  description = "External IP for Ops Manager"
  value       = var.ops_manager_external_ip
}
```

**Step 2: Commit**

```bash
git add terraform/nsxt/outputs.tf
git commit -m "feat(nsxt): add outputs for segment names, pool names, VIPs"
```

---

### Task 9: Create NSX-T tfvars Example

**Files:**
- Create: `terraform/nsxt/terraform.tfvars.example`

**Step 1: Create example tfvars**

```hcl
# terraform/nsxt/terraform.tfvars.example
# Copy to terraform.tfvars and fill in values

nsxt_host            = "nsx01.vcf.lab"
nsxt_username        = "admin"
nsxt_password        = "CHANGE_ME"
allow_unverified_ssl = true

environment_name     = "tas"
edge_cluster_name    = "edge-cluster-01"
transport_zone_name  = "overlay-tz"
t0_gateway_name      = "T0-Gateway"

# Network CIDRs
infrastructure_cidr = "10.0.1.0/24"
deployment_cidr     = "10.0.2.0/24"
services_cidr       = "10.0.3.0/24"

# External IPs
nat_gateway_ip           = "31.31.10.1"
ops_manager_external_ip  = "31.31.10.10"
ops_manager_internal_ip  = "10.0.1.10"
web_lb_vip               = "31.31.10.20"
ssh_lb_vip               = "31.31.10.21"
tcp_lb_vip               = "31.31.10.22"

# Container networking
external_ip_pool_start   = "31.31.10.100"
external_ip_pool_end     = "31.31.10.200"
container_ip_block_cidr  = "10.12.0.0/14"
```

**Step 2: Commit**

```bash
git add terraform/nsxt/terraform.tfvars.example
git commit -m "docs(nsxt): add example tfvars file"
```

---

## Phase 3: vSphere Resources

### Task 10: Create vSphere Data Sources

**Files:**
- Create: `terraform/vsphere/data.tf`

**Step 1: Create data sources**

```hcl
# terraform/vsphere/data.tf

data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "infrastructure_host" {
  name          = var.infrastructure_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "az1_host" {
  name          = var.az1_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "az2_host" {
  name          = var.az2_host
  datacenter_id = data.vsphere_datacenter.dc.id
}
```

**Step 2: Commit**

```bash
git add terraform/vsphere/data.tf
git commit -m "feat(vsphere): add data sources for datacenter, cluster, hosts"
```

---

### Task 11: Create Resource Pools

**Files:**
- Create: `terraform/vsphere/resource_pools.tf`

**Step 1: Create resource pools**

```hcl
# terraform/vsphere/resource_pools.tf

# Resource pool for infrastructure (Ops Manager, BOSH Director)
resource "vsphere_resource_pool" "infrastructure" {
  name                    = "${var.environment_name}-infrastructure"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}

# Resource pool for AZ1 workloads
resource "vsphere_resource_pool" "az1" {
  name                    = "${var.environment_name}-az1"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}

# Resource pool for AZ2 workloads
resource "vsphere_resource_pool" "az2" {
  name                    = "${var.environment_name}-az2"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}
```

**Step 2: Commit**

```bash
git add terraform/vsphere/resource_pools.tf
git commit -m "feat(vsphere): add resource pools for infrastructure, az1, az2"
```

---

### Task 12: Create VM Folders

**Files:**
- Create: `terraform/vsphere/folders.tf`

**Step 1: Create VM folders**

```hcl
# terraform/vsphere/folders.tf

# Parent folder for all TAS resources
resource "vsphere_folder" "tas" {
  path          = var.environment_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Folder for TAS VMs
resource "vsphere_folder" "vms" {
  path          = "${vsphere_folder.tas.path}/vms"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Folder for BOSH stemcell templates
resource "vsphere_folder" "templates" {
  path          = "${vsphere_folder.tas.path}/templates"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}
```

**Step 2: Commit**

```bash
git add terraform/vsphere/folders.tf
git commit -m "feat(vsphere): add VM folders for TAS"
```

---

### Task 13: Create DRS Rules

**Files:**
- Create: `terraform/vsphere/drs_rules.tf`

**Step 1: Create DRS VM-Host affinity rules**

```hcl
# terraform/vsphere/drs_rules.tf

# DRS rule to prefer infrastructure VMs on esx01
resource "vsphere_compute_cluster_vm_host_rule" "infrastructure_affinity" {
  name                     = "${var.environment_name}-infrastructure-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.infrastructure.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.infrastructure_hosts.name
  mandatory                = false  # Soft rule - prefer but don't require
}

resource "vsphere_compute_cluster_vm_group" "infrastructure" {
  name               = "${var.environment_name}-infrastructure-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  # VMs will be added dynamically by BOSH
}

resource "vsphere_compute_cluster_host_group" "infrastructure_hosts" {
  name               = "${var.environment_name}-infrastructure-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.infrastructure_host.id]
}

# DRS rule to prefer AZ1 VMs on esx02
resource "vsphere_compute_cluster_vm_host_rule" "az1_affinity" {
  name                     = "${var.environment_name}-az1-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.az1.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.az1_hosts.name
  mandatory                = false
}

resource "vsphere_compute_cluster_vm_group" "az1" {
  name               = "${var.environment_name}-az1-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
}

resource "vsphere_compute_cluster_host_group" "az1_hosts" {
  name               = "${var.environment_name}-az1-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.az1_host.id]
}

# DRS rule to prefer AZ2 VMs on esx03
resource "vsphere_compute_cluster_vm_host_rule" "az2_affinity" {
  name                     = "${var.environment_name}-az2-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.az2.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.az2_hosts.name
  mandatory                = false
}

resource "vsphere_compute_cluster_vm_group" "az2" {
  name               = "${var.environment_name}-az2-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
}

resource "vsphere_compute_cluster_host_group" "az2_hosts" {
  name               = "${var.environment_name}-az2-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.az2_host.id]
}
```

**Step 2: Commit**

```bash
git add terraform/vsphere/drs_rules.tf
git commit -m "feat(vsphere): add DRS VM-Host affinity rules for AZ placement"
```

---

### Task 14: Create vSphere Outputs

**Files:**
- Create: `terraform/vsphere/outputs.tf`

**Step 1: Create outputs**

```hcl
# terraform/vsphere/outputs.tf

output "datacenter_name" {
  description = "Datacenter name"
  value       = data.vsphere_datacenter.dc.name
}

output "cluster_name" {
  description = "Cluster name"
  value       = data.vsphere_compute_cluster.cluster.name
}

output "datastore_name" {
  description = "Datastore name"
  value       = data.vsphere_datastore.datastore.name
}

# Resource pool paths
output "infrastructure_resource_pool" {
  description = "Resource pool path for infrastructure VMs"
  value       = vsphere_resource_pool.infrastructure.name
}

output "az1_resource_pool" {
  description = "Resource pool path for AZ1 VMs"
  value       = vsphere_resource_pool.az1.name
}

output "az2_resource_pool" {
  description = "Resource pool path for AZ2 VMs"
  value       = vsphere_resource_pool.az2.name
}

# Folder paths
output "vm_folder" {
  description = "VM folder path"
  value       = vsphere_folder.vms.path
}

output "template_folder" {
  description = "Template folder path"
  value       = vsphere_folder.templates.path
}

# Host names
output "infrastructure_host" {
  description = "Infrastructure host name"
  value       = var.infrastructure_host
}

output "az1_host" {
  description = "AZ1 host name"
  value       = var.az1_host
}

output "az2_host" {
  description = "AZ2 host name"
  value       = var.az2_host
}
```

**Step 2: Commit**

```bash
git add terraform/vsphere/outputs.tf
git commit -m "feat(vsphere): add outputs for resource pools, folders, hosts"
```

---

### Task 15: Create vSphere tfvars Example

**Files:**
- Create: `terraform/vsphere/terraform.tfvars.example`

**Step 1: Create example tfvars**

```hcl
# terraform/vsphere/terraform.tfvars.example
# Copy to terraform.tfvars and fill in values

vcenter_host         = "vc01.vcf.lab"
vcenter_username     = "administrator@vsphere.local"
vcenter_password     = "CHANGE_ME"
allow_unverified_ssl = true

datacenter_name = "VCF-DC"
cluster_name    = "VCF-Mgmt-Cluster"
datastore_name  = "vsan-ds"

environment_name = "tas"

# Hosts for DRS rules
infrastructure_host = "esx01.vcf.lab"
az1_host            = "esx02.vcf.lab"
az2_host            = "esx03.vcf.lab"
```

**Step 2: Commit**

```bash
git add terraform/vsphere/terraform.tfvars.example
git commit -m "docs(vsphere): add example tfvars file"
```

---

## Phase 4: Certificate Generation

### Task 16: Create Certificate Resources

**Files:**
- Create: `terraform/certs/main.tf`

**Step 1: Create CA and certificates**

```hcl
# terraform/certs/main.tf

# Root CA
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "TAS Homelab CA"
    organization = var.organization
  }

  validity_period_hours = var.validity_period_hours
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Ops Manager certificate
resource "tls_private_key" "opsman" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "opsman" {
  private_key_pem = tls_private_key.opsman.private_key_pem

  subject {
    common_name  = "opsman.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "opsman.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "opsman" {
  cert_request_pem   = tls_cert_request.opsman.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# TAS System domain certificate (wildcard)
resource "tls_private_key" "tas_system" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "tas_system" {
  private_key_pem = tls_private_key.tas_system.private_key_pem

  subject {
    common_name  = "*.sys.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "*.sys.${var.base_domain}",
    "*.login.sys.${var.base_domain}",
    "*.uaa.sys.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "tas_system" {
  cert_request_pem   = tls_cert_request.tas_system.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# TAS Apps domain certificate (wildcard)
resource "tls_private_key" "tas_apps" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "tas_apps" {
  private_key_pem = tls_private_key.tas_apps.private_key_pem

  subject {
    common_name  = "*.apps.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "*.apps.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "tas_apps" {
  cert_request_pem   = tls_cert_request.tas_apps.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Write certificates to files
resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca.cert_pem
  filename = "${var.output_path}/ca.crt"
}

resource "local_file" "opsman_cert" {
  content  = tls_locally_signed_cert.opsman.cert_pem
  filename = "${var.output_path}/opsman.crt"
}

resource "local_file" "opsman_key" {
  content         = tls_private_key.opsman.private_key_pem
  filename        = "${var.output_path}/opsman.key"
  file_permission = "0600"
}

resource "local_file" "tas_system_cert" {
  content  = tls_locally_signed_cert.tas_system.cert_pem
  filename = "${var.output_path}/tas-system.crt"
}

resource "local_file" "tas_system_key" {
  content         = tls_private_key.tas_system.private_key_pem
  filename        = "${var.output_path}/tas-system.key"
  file_permission = "0600"
}

resource "local_file" "tas_apps_cert" {
  content  = tls_locally_signed_cert.tas_apps.cert_pem
  filename = "${var.output_path}/tas-apps.crt"
}

resource "local_file" "tas_apps_key" {
  content         = tls_private_key.tas_apps.private_key_pem
  filename        = "${var.output_path}/tas-apps.key"
  file_permission = "0600"
}
```

**Step 2: Commit**

```bash
git add terraform/certs/main.tf
git commit -m "feat(certs): add CA and certificate generation"
```

---

### Task 17: Create Certificate Outputs

**Files:**
- Create: `terraform/certs/outputs.tf`

**Step 1: Create outputs**

```hcl
# terraform/certs/outputs.tf

output "ca_cert" {
  description = "CA certificate PEM"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "opsman_cert" {
  description = "Ops Manager certificate PEM"
  value       = tls_locally_signed_cert.opsman.cert_pem
  sensitive   = true
}

output "opsman_key" {
  description = "Ops Manager private key PEM"
  value       = tls_private_key.opsman.private_key_pem
  sensitive   = true
}

output "tas_system_cert" {
  description = "TAS system domain certificate PEM"
  value       = tls_locally_signed_cert.tas_system.cert_pem
  sensitive   = true
}

output "tas_system_key" {
  description = "TAS system domain private key PEM"
  value       = tls_private_key.tas_system.private_key_pem
  sensitive   = true
}

output "tas_apps_cert" {
  description = "TAS apps domain certificate PEM"
  value       = tls_locally_signed_cert.tas_apps.cert_pem
  sensitive   = true
}

output "tas_apps_key" {
  description = "TAS apps domain private key PEM"
  value       = tls_private_key.tas_apps.private_key_pem
  sensitive   = true
}

output "generated_files_path" {
  description = "Path where certificate files were written"
  value       = var.output_path
}
```

**Step 2: Commit**

```bash
git add terraform/certs/outputs.tf
git commit -m "feat(certs): add certificate outputs"
```

---

## Phase 5: Platform Automation Foundation Config

### Task 18: Create Foundation Directory Structure

**Files:**
- Create: `foundations/vcf/config/.gitkeep`
- Create: `foundations/vcf/vars/.gitkeep`
- Create: `foundations/vcf/versions/.gitkeep`
- Create: `foundations/vcf/state/.gitkeep`

**Step 1: Create directory structure**

```bash
mkdir -p foundations/vcf/{config,vars,versions,state}
touch foundations/vcf/config/.gitkeep
touch foundations/vcf/vars/.gitkeep
touch foundations/vcf/versions/.gitkeep
touch foundations/vcf/state/.gitkeep
```

**Step 2: Commit**

```bash
git add foundations/
git commit -m "feat(foundations): create vcf foundation directory structure"
```

---

### Task 19: Create Ops Manager Config

**Files:**
- Create: `foundations/vcf/config/opsman.yml`

**Step 1: Create Ops Manager config**

```yaml
# foundations/vcf/config/opsman.yml
---
opsman-configuration:
  vsphere:
    vcenter:
      url: ((vcenter_host))
      username: ((vcenter_username))
      password: ((vcenter_password))
      datacenter: ((datacenter_name))
      datastore: ((datastore_name))
      ca_cert: ((vcenter_ca_cert))
    insecure: 1
    resource_pool: /((datacenter_name))/host/((cluster_name))/Resources/((infrastructure_resource_pool))
    folder: /((datacenter_name))/vm/((vm_folder))
    network: ((infrastructure_segment_name))
    private_ip: ((ops_manager_private_ip))
    netmask: ((ops_manager_netmask))
    gateway: ((ops_manager_gateway))
    dns: ((dns_servers))
    ntp: ((ntp_servers))
    ssh_public_key: ((ops_manager_ssh_public_key))
    hostname: ((ops_manager_hostname))
    disk_type: thin
    ssh_password: ((ops_manager_ssh_password))
    decryption_passphrase: ((ops_manager_decryption_passphrase))
```

**Step 2: Commit**

```bash
git add foundations/vcf/config/opsman.yml
git commit -m "feat(foundations): add Ops Manager deployment config"
```

---

### Task 20: Create Director Config

**Files:**
- Create: `foundations/vcf/config/director.yml`

**Step 1: Create BOSH Director config**

```yaml
# foundations/vcf/config/director.yml
---
az-configuration:
  - name: az1
    clusters:
      - cluster: ((cluster_name))
        resource_pool: ((az1_resource_pool))
        drs_rule: "SHOULD"
  - name: az2
    clusters:
      - cluster: ((cluster_name))
        resource_pool: ((az2_resource_pool))
        drs_rule: "SHOULD"

network-assignment:
  network:
    name: infrastructure
  singleton_availability_zone:
    name: az1

networks-configuration:
  icmp_checks_enabled: false
  networks:
    - name: infrastructure
      subnets:
        - iaas_identifier: ((infrastructure_segment_name))
          cidr: ((infrastructure_cidr))
          gateway: ((infrastructure_gateway))
          reserved_ip_ranges: ((infrastructure_reserved_ips))
          dns: ((dns_servers))
          availability_zone_names:
            - az1
            - az2
    - name: deployment
      subnets:
        - iaas_identifier: ((deployment_segment_name))
          cidr: ((deployment_cidr))
          gateway: ((deployment_gateway))
          reserved_ip_ranges: ((deployment_reserved_ips))
          dns: ((dns_servers))
          availability_zone_names:
            - az1
            - az2
    - name: services
      subnets:
        - iaas_identifier: ((services_segment_name))
          cidr: ((services_cidr))
          gateway: ((services_gateway))
          reserved_ip_ranges: ((services_reserved_ips))
          dns: ((dns_servers))
          availability_zone_names:
            - az1
            - az2

properties-configuration:
  director_configuration:
    ntp_servers_string: ((ntp_servers))
    resurrector_enabled: true
    post_deploy_enabled: true
    retry_bosh_deploys: true
  iaas_configuration:
    vcenter_host: ((vcenter_host))
    vcenter_username: ((vcenter_username))
    vcenter_password: ((vcenter_password))
    datacenter: ((datacenter_name))
    disk_type: thin
    ephemeral_datastores_string: ((datastore_name))
    persistent_datastores_string: ((datastore_name))
    bosh_vm_folder: ((vm_folder))
    bosh_template_folder: ((template_folder))
    bosh_disk_path: ((disk_folder))
    ssl_verification_enabled: false
    nsx_networking_enabled: true
    nsx_mode: nsx-t
    nsx_address: ((nsxt_host))
    nsx_username: ((nsxt_username))
    nsx_password: ((nsxt_password))
    nsx_ca_certificate: ((nsxt_ca_cert))
  security_configuration:
    trusted_certificates: ((trusted_certificates))
    generate_vm_passwords: true

resource-configuration:
  director:
    internet_connected: false
  compilation:
    internet_connected: false

vmextensions-configuration: []
```

**Step 2: Commit**

```bash
git add foundations/vcf/config/director.yml
git commit -m "feat(foundations): add BOSH Director config with NSX-T and AZs"
```

---

### Task 21: Create Foundation Variables

**Files:**
- Create: `foundations/vcf/vars/director.yml`

**Step 1: Create director variables**

```yaml
# foundations/vcf/vars/director.yml
---
# vCenter
vcenter_host: vc01.vcf.lab
vcenter_username: ((vcenter_username))
vcenter_password: ((vcenter_password))
vcenter_ca_cert: ""
datacenter_name: VCF-DC
cluster_name: VCF-Mgmt-Cluster
datastore_name: vsan-ds

# Ops Manager
ops_manager_hostname: opsman.tas.vcf.lab
ops_manager_private_ip: 10.0.1.10
ops_manager_netmask: 255.255.255.0
ops_manager_gateway: 10.0.1.1
ops_manager_ssh_public_key: ((ops_manager_ssh_public_key))
ops_manager_ssh_password: ((ops_manager_ssh_password))
ops_manager_decryption_passphrase: ((ops_manager_decryption_passphrase))

# Resource pools
infrastructure_resource_pool: tas-infrastructure
az1_resource_pool: tas-az1
az2_resource_pool: tas-az2

# Folders
vm_folder: tas/vms
template_folder: tas/templates
disk_folder: tas/disks

# NSX-T
nsxt_host: nsx01.vcf.lab
nsxt_username: ((nsxt_username))
nsxt_password: ((nsxt_password))
nsxt_ca_cert: ""

# Networks - Infrastructure
infrastructure_segment_name: tas-Infrastructure
infrastructure_cidr: 10.0.1.0/24
infrastructure_gateway: 10.0.1.1
infrastructure_reserved_ips: 10.0.1.1-10.0.1.9

# Networks - Deployment
deployment_segment_name: tas-Deployment
deployment_cidr: 10.0.2.0/24
deployment_gateway: 10.0.2.1
deployment_reserved_ips: 10.0.2.1-10.0.2.9

# Networks - Services
services_segment_name: tas-Services
services_cidr: 10.0.3.0/24
services_gateway: 10.0.3.1
services_reserved_ips: 10.0.3.1-10.0.3.9

# DNS and NTP
dns_servers: 192.168.10.2
ntp_servers: pool.ntp.org

# Certificates
trusted_certificates: ((trusted_certificates))
```

**Step 2: Commit**

```bash
git add foundations/vcf/vars/director.yml
git commit -m "feat(foundations): add director variables for VCF environment"
```

---

### Task 22: Create Product Versions

**Files:**
- Create: `foundations/vcf/versions/versions.yml`

**Step 1: Create versions file**

```yaml
# foundations/vcf/versions/versions.yml
---
# Ops Manager
opsman_version: "3.0.*"
opsman_glob: "ops-manager-vsphere-*.ova"

# TAS
tas_version: "6.0.6"
tas_glob: "cf-*.pivotal"

# Stemcell
stemcell_version: "1.*"
stemcell_iaas: vsphere
stemcell_os: ubuntu-jammy
```

**Step 2: Commit**

```bash
git add foundations/vcf/versions/versions.yml
git commit -m "feat(foundations): add product versions for TAS 6.0.6"
```

---

## Phase 6: DNS Setup Script

### Task 23: Create DNS Setup Script

**Files:**
- Create: `scripts/setup-dns.sh`

**Step 1: Create DNS setup script**

```bash
#!/usr/bin/env bash
# scripts/setup-dns.sh
# Add TAS DNS entries to Pi-hole/Unbound

set -euo pipefail

DNS_SERVER="${DNS_SERVER:-192.168.10.2}"
DNS_USER="${DNS_USER:-root}"

# DNS entries to add
declare -A DNS_ENTRIES=(
    ["opsman.tas.vcf.lab"]="31.31.10.10"
    ["*.sys.tas.vcf.lab"]="31.31.10.20"
    ["*.apps.tas.vcf.lab"]="31.31.10.20"
    ["ssh.sys.tas.vcf.lab"]="31.31.10.21"
    ["tcp.tas.vcf.lab"]="31.31.10.22"
)

echo "DNS entries to configure:"
for hostname in "${!DNS_ENTRIES[@]}"; do
    ip="${DNS_ENTRIES[$hostname]}"
    echo "  $hostname -> $ip"
done

echo ""
echo "To add these entries to Pi-hole/Unbound on $DNS_SERVER:"
echo ""
echo "1. SSH to DNS server:"
echo "   ssh $DNS_USER@$DNS_SERVER"
echo ""
echo "2. Add entries to /etc/unbound/unbound.conf.d/tas.conf:"
echo ""
cat << 'EOF'
server:
    # TAS Ops Manager
    local-data: "opsman.tas.vcf.lab. A 31.31.10.10"
    local-data-ptr: "31.31.10.10 opsman.tas.vcf.lab"

    # TAS System Domain (wildcard)
    local-zone: "sys.tas.vcf.lab." redirect
    local-data: "sys.tas.vcf.lab. A 31.31.10.20"

    # TAS Apps Domain (wildcard)
    local-zone: "apps.tas.vcf.lab." redirect
    local-data: "apps.tas.vcf.lab. A 31.31.10.20"

    # TAS SSH
    local-data: "ssh.sys.tas.vcf.lab. A 31.31.10.21"

    # TAS TCP Router
    local-data: "tcp.tas.vcf.lab. A 31.31.10.22"
EOF
echo ""
echo "3. Restart Unbound:"
echo "   systemctl restart unbound"
echo ""
echo "4. Test resolution:"
echo "   dig @$DNS_SERVER opsman.tas.vcf.lab"
echo "   dig @$DNS_SERVER test.sys.tas.vcf.lab"
echo "   dig @$DNS_SERVER myapp.apps.tas.vcf.lab"
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/setup-dns.sh
git add scripts/setup-dns.sh
git commit -m "feat(scripts): add DNS setup script for Pi-hole/Unbound"
```

---

## Phase 7: Validation and Testing

### Task 24: Create Terraform Validation Script

**Files:**
- Create: `scripts/validate-terraform.sh`

**Step 1: Create validation script**

```bash
#!/usr/bin/env bash
# scripts/validate-terraform.sh
# Validate Terraform configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Validating Terraform configurations..."
echo ""

for module in nsxt vsphere certs; do
    module_path="$PROJECT_ROOT/terraform/$module"
    if [[ -d "$module_path" ]]; then
        echo "=== Validating $module module ==="
        cd "$module_path"
        terraform init -backend=false
        terraform validate
        terraform fmt -check -diff
        echo "✓ $module module is valid"
        echo ""
    fi
done

echo "All Terraform modules validated successfully!"
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/validate-terraform.sh
git add scripts/validate-terraform.sh
git commit -m "feat(scripts): add Terraform validation script"
```

---

### Task 25: Create README

**Files:**
- Create: `README.md`

**Step 1: Create project README**

```markdown
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
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add project README"
```

---

### Task 26: Final Commit and Push

**Step 1: Verify all changes committed**

```bash
git status
git log --oneline -15
```

**Step 2: Push to remote**

```bash
git push origin main
```

---

## Execution Summary

After completing all tasks:

1. **NSX-T paving** creates: T1 gateways, segments, NAT rules, LB pools/virtual servers, IP pools
2. **vSphere paving** creates: Resource pools, VM folders, DRS affinity rules
3. **Certificates** generates: CA, Ops Manager cert, TAS system/apps wildcard certs
4. **Foundation config** provides: Ops Manager and Director configs for Platform Automation
5. **DNS script** documents: Pi-hole/Unbound entries needed

## Next Steps (Manual)

After Terraform apply:

1. Run `scripts/setup-dns.sh` and configure Pi-hole
2. Configure Concourse pipeline in tanzu-homelab
3. Trigger pipeline to deploy Ops Manager
4. Configure and deploy BOSH Director
5. Upload and configure TAS 6.0.6 tile
6. Apply changes
