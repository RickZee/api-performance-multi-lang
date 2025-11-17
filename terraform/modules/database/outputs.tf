output "endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "RDS instance address (hostname)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Database master username"
  value       = aws_db_instance.this.username
}

output "security_group_id" {
  description = "Security group ID for the database"
  value       = aws_security_group.rds.id
}

output "subnet_group_id" {
  description = "DB subnet group ID"
  value       = aws_db_subnet_group.this.id
}

output "connection_string" {
  description = "Database connection string (without password)"
  value       = "postgresql://${aws_db_instance.this.username}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
  sensitive   = false
}

