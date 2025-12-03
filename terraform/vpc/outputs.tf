# ABOUTME: Output values from TAS VPC Terraform module
# ABOUTME: Exports VPC and subnet information for use by other modules

output "vpc_id" {
  description = "ID of the TAS VPC"
  value       = data.nsxt_policy_vpc.tas_vpc.id
}

output "vpc_path" {
  description = "Policy path of the TAS VPC"
  value       = data.nsxt_policy_vpc.tas_vpc.path
}

output "infrastructure_subnet_id" {
  description = "ID of the infrastructure subnet"
  value       = data.nsxt_policy_vpc_subnet.infrastructure.id
}

output "infrastructure_subnet_path" {
  description = "Policy path of the infrastructure subnet"
  value       = data.nsxt_policy_vpc_subnet.infrastructure.path
}

output "deployment_subnet_id" {
  description = "ID of the deployment subnet"
  value       = data.nsxt_policy_vpc_subnet.deployment.id
}

output "deployment_subnet_path" {
  description = "Policy path of the deployment subnet"
  value       = data.nsxt_policy_vpc_subnet.deployment.path
}

output "services_subnet_id" {
  description = "ID of the services subnet"
  value       = data.nsxt_policy_vpc_subnet.services.id
}

output "services_subnet_path" {
  description = "Policy path of the services subnet"
  value       = data.nsxt_policy_vpc_subnet.services.path
}

output "ops_manager_external_ip" {
  description = "External IP for Ops Manager"
  value       = var.ops_manager_external_ip
}

output "web_lb_vip" {
  description = "External IP for web load balancer"
  value       = var.web_lb_vip
}

output "ssh_lb_vip" {
  description = "External IP for SSH load balancer"
  value       = var.ssh_lb_vip
}

output "tcp_lb_vip" {
  description = "External IP for TCP router load balancer"
  value       = var.tcp_lb_vip
}
