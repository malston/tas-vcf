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
