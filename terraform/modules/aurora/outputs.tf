output "cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Aurora cluster endpoint (writer)"
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master username"
  value       = aws_rds_cluster.this.master_username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for Aurora"
  value       = aws_security_group.aurora.id
}

output "connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${aws_rds_cluster.this.master_username}:${aws_rds_cluster.this.master_password}@${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${aws_rds_cluster.this.database_name}"
  sensitive   = true
}

output "r2dbc_connection_string" {
  description = "R2DBC connection string for Spring Boot"
  value       = "r2dbc:postgresql://${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${aws_rds_cluster.this.database_name}"
  sensitive   = false
}

output "public_endpoint" {
  description = "Public endpoint URL (if publicly accessible)"
  value       = var.publicly_accessible ? aws_rds_cluster.this.endpoint : null
}

output "connection_instructions" {
  description = "Instructions for connecting to Aurora from Confluent Cloud"
  value = var.publicly_accessible ? (
    <<-EOT
Aurora is configured for public internet access.

Endpoint: ${aws_rds_cluster.this.endpoint}
Port: ${aws_rds_cluster.this.port}
Database: ${aws_rds_cluster.this.database_name}

Connector Configuration (Postgres CDC Source V2 - Debezium):
- Connector Type: Postgres CDC Source V2 (Debezium)
- database.hostname = "${aws_rds_cluster.this.endpoint}"
- database.port = "${aws_rds_cluster.this.port}"
- database.user = "${aws_rds_cluster.this.master_username}"
- database.password = "<your-password>"
- database.dbname = "${aws_rds_cluster.this.database_name}"
- plugin.name = "pgoutput"
- connector.class = "PostgresCdcSource" (for Confluent Cloud managed connector)

Security:
- SSL/TLS is required: Use sslmode=require in connection string
- Security group is ${local.use_restricted_access ? "restricted to Confluent Cloud IP ranges" : "allowing all IPs (0.0.0.0/0)"}
${local.use_restricted_access ? "- Confluent Cloud CIDRs: ${join(", ", local.confluent_cloud_cidrs_validated)}" : "- WARNING: Unrestricted access - consider adding confluent_cloud_cidrs"}

For detailed setup, see: terraform/PUBLIC_ACCESS_SETUP.md
EOT
  ) : (
    <<-EOT
Aurora is configured for private access only.
Use AWS PrivateLink for Confluent Cloud connectivity.
EOT
  )
}
