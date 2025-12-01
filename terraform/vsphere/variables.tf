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
