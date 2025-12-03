# ABOUTME: Terraform version constraints and required providers for VPC module
# ABOUTME: Specifies NSX-T provider for managing VPC resources
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    nsxt = {
      source  = "vmware/nsxt"
      version = "~> 3.4"
    }
  }
}
