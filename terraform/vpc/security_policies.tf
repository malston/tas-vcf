# ABOUTME: Security policies for TAS VPC
# ABOUTME: Defines distributed firewall rules for inter-subnet and external communication

# Security policy for infrastructure subnet
resource "nsxt_policy_security_policy" "tas_infrastructure" {
  display_name = "tas-infrastructure-security-policy"
  description  = "Security policy for TAS infrastructure subnet (Ops Manager, BOSH)"
  category     = "Application"
  scope        = [data.nsxt_policy_vpc_subnet.infrastructure.path]

  rule {
    display_name       = "allow-ssh-from-external"
    description        = "Allow SSH to infrastructure subnet from external"
    action             = "ALLOW"
    logged             = true
    destination_groups = [data.nsxt_policy_vpc_subnet.infrastructure.path]
    services           = ["/infra/services/SSH"]
  }

  rule {
    display_name       = "allow-https-from-external"
    description        = "Allow HTTPS to infrastructure subnet from external"
    action             = "ALLOW"
    logged             = true
    destination_groups = [data.nsxt_policy_vpc_subnet.infrastructure.path]
    services           = ["/infra/services/HTTPS"]
  }

  rule {
    display_name       = "allow-internal-vpc"
    description        = "Allow all traffic within VPC subnets"
    action             = "ALLOW"
    logged             = false
    source_groups      = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
    destination_groups = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
  }

  rule {
    display_name       = "allow-outbound"
    description        = "Allow outbound internet access"
    action             = "ALLOW"
    logged             = false
    source_groups      = [data.nsxt_policy_vpc_subnet.infrastructure.path]
  }
}

# Security policy for deployment subnet
resource "nsxt_policy_security_policy" "tas_deployment" {
  display_name = "tas-deployment-security-policy"
  description  = "Security policy for TAS deployment subnet (runtime VMs)"
  category     = "Application"
  scope        = [data.nsxt_policy_vpc_subnet.deployment.path]

  rule {
    display_name       = "allow-http-https-from-external"
    description        = "Allow HTTP/HTTPS to deployment subnet from external"
    action             = "ALLOW"
    logged             = true
    destination_groups = [data.nsxt_policy_vpc_subnet.deployment.path]
    services           = [
      "/infra/services/HTTP",
      "/infra/services/HTTPS"
    ]
  }

  rule {
    display_name       = "allow-internal-vpc"
    description        = "Allow all traffic within VPC subnets"
    action             = "ALLOW"
    logged             = false
    source_groups      = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
    destination_groups = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
  }

  rule {
    display_name       = "allow-outbound"
    description        = "Allow outbound internet access"
    action             = "ALLOW"
    logged             = false
    source_groups      = [data.nsxt_policy_vpc_subnet.deployment.path]
  }
}

# Security policy for services subnet
resource "nsxt_policy_security_policy" "tas_services" {
  display_name = "tas-services-security-policy"
  description  = "Security policy for TAS services subnet (service instances)"
  category     = "Application"
  scope        = [data.nsxt_policy_vpc_subnet.services.path]

  rule {
    display_name       = "allow-internal-vpc"
    description        = "Allow all traffic within VPC subnets"
    action             = "ALLOW"
    logged             = false
    source_groups      = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
    destination_groups = [
      data.nsxt_policy_vpc_subnet.infrastructure.path,
      data.nsxt_policy_vpc_subnet.deployment.path,
      data.nsxt_policy_vpc_subnet.services.path
    ]
  }

  rule {
    display_name       = "allow-outbound"
    description        = "Allow outbound internet access"
    action             = "ALLOW"
    logged             = false
    source_groups      = [data.nsxt_policy_vpc_subnet.services.path]
  }
}
