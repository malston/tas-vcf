# terraform/certs/outputs.tf

output "ca_cert" {
  description = "CA certificate PEM"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "opsman_cert" {
  description = "Ops Manager certificate PEM"
  value       = tls_locally_signed_cert.opsman.cert_pem
  sensitive   = true
}

output "opsman_key" {
  description = "Ops Manager private key PEM"
  value       = tls_private_key.opsman.private_key_pem
  sensitive   = true
}

output "tas_system_cert" {
  description = "TAS system domain certificate PEM"
  value       = tls_locally_signed_cert.tas_system.cert_pem
  sensitive   = true
}

output "tas_system_key" {
  description = "TAS system domain private key PEM"
  value       = tls_private_key.tas_system.private_key_pem
  sensitive   = true
}

output "tas_apps_cert" {
  description = "TAS apps domain certificate PEM"
  value       = tls_locally_signed_cert.tas_apps.cert_pem
  sensitive   = true
}

output "tas_apps_key" {
  description = "TAS apps domain private key PEM"
  value       = tls_private_key.tas_apps.private_key_pem
  sensitive   = true
}

output "generated_files_path" {
  description = "Path where certificate files were written"
  value       = var.output_path
}
