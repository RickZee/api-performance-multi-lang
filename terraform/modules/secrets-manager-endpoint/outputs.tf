output "secrets_manager_endpoint_id" {
  description = "ID of the Secrets Manager VPC endpoint"
  value       = aws_vpc_endpoint.secrets_manager.id
}

output "security_group_id" {
  description = "Security group ID for Secrets Manager endpoint"
  value       = aws_security_group.secrets_manager_endpoint.id
}

