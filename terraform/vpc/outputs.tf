# ABOUTME: Output values from TAS VPC Terraform module
# ABOUTME: Documents configured VPC and subnet information

output "vpc_name" {
  description = "Name of the TAS VPC"
  value       = var.vpc_name
}

output "vpc_cidr" {
  description = "Private CIDR of the TAS VPC"
  value       = var.vpc_private_cidr
}

output "infrastructure_subnet_cidr" {
  description = "CIDR of the infrastructure subnet"
  value       = var.infrastructure_subnet_cidr
}

output "deployment_subnet_cidr" {
  description = "CIDR of the deployment subnet"
  value       = var.deployment_subnet_cidr
}

output "services_subnet_cidr" {
  description = "CIDR of the services subnet"
  value       = var.services_subnet_cidr
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
