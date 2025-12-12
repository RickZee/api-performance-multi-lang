output "proxy_id" {
  description = "RDS Proxy ID"
  value       = aws_db_proxy.this.id
}

output "proxy_arn" {
  description = "RDS Proxy ARN"
  value       = aws_db_proxy.this.arn
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint (use this in connection strings instead of Aurora endpoint)"
  value       = aws_db_proxy.this.endpoint
}

output "proxy_name" {
  description = "RDS Proxy name"
  value       = aws_db_proxy.this.name
}

output "proxy_target_group_arn" {
  description = "RDS Proxy default target group ARN"
  value       = aws_db_proxy_default_target_group.this.arn
}

output "security_group_id" {
  description = "Security group ID for RDS Proxy"
  value       = aws_security_group.rds_proxy.id
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret storing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}

output "connection_string_template" {
  description = "PostgreSQL connection string template using RDS Proxy endpoint (database name must be appended)"
  value       = "postgresql://${var.database_user}:${var.database_password}@${aws_db_proxy.this.endpoint}:5432"
  sensitive   = true
}

