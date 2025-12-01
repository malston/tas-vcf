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
