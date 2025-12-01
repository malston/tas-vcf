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
