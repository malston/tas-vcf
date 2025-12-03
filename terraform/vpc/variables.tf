# ABOUTME: Input variables for TAS VPC Terraform module
# ABOUTME: Defines NSX connection settings, VPC configuration, and network CIDRs

# NSX Connection
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

# VPC Configuration
variable "vpc_name" {
  description = "Name of the VPC (must be created manually via NSX UI)"
  type        = string
  default     = "tas-vpc"
}

variable "vpc_private_cidr" {
  description = "Private IPv4 CIDR for VPC (set during manual creation)"
  type        = string
  default     = "172.20.0.0/16"
}

# Subnet Configuration
variable "infrastructure_subnet_cidr" {
  description = "CIDR for infrastructure subnet (Ops Manager, BOSH)"
  type        = string
  default     = "172.20.0.0/24"
}

variable "deployment_subnet_cidr" {
  description = "CIDR for deployment subnet (TAS Runtime VMs)"
  type        = string
  default     = "172.20.1.0/24"
}

variable "services_subnet_cidr" {
  description = "CIDR for services subnet (Service Instances)"
  type        = string
  default     = "172.20.2.0/24"
}

variable "dns_servers" {
  description = "DNS servers for DHCP configuration"
  type        = list(string)
  default     = ["192.168.10.2"]
}

# External IP Configuration
variable "ops_manager_external_ip" {
  description = "External IP to assign to Ops Manager VM"
  type        = string
  default     = "31.31.10.10"
}

variable "web_lb_vip" {
  description = "External IP for web (HTTP/HTTPS) load balancer"
  type        = string
  default     = "31.31.10.20"
}

variable "ssh_lb_vip" {
  description = "External IP for SSH load balancer"
  type        = string
  default     = "31.31.10.21"
}

variable "tcp_lb_vip" {
  description = "External IP for TCP router load balancer"
  type        = string
  default     = "31.31.10.22"
}

# Tags
variable "environment_name" {
  description = "Environment identifier for resource tagging"
  type        = string
  default     = "tas"
}
