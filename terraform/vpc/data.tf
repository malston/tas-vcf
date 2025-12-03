# ABOUTME: Data sources for referencing existing NSX resources
# ABOUTME: Imports VPC and related resources created manually via NSX UI

# Reference the manually created VPC
data "nsxt_policy_vpc" "tas_vpc" {
  display_name = var.vpc_name
}

# Reference the VPC subnets created manually
data "nsxt_policy_vpc_subnet" "infrastructure" {
  display_name   = "tas-infrastructure"
  parent_path    = data.nsxt_policy_vpc.tas_vpc.path
}

data "nsxt_policy_vpc_subnet" "deployment" {
  display_name   = "tas-deployment"
  parent_path    = data.nsxt_policy_vpc.tas_vpc.path
}

data "nsxt_policy_vpc_subnet" "services" {
  display_name   = "tas-services"
  parent_path    = data.nsxt_policy_vpc.tas_vpc.path
}
