output "cluster_arn" {
  description = "Aurora DSQL cluster ARN"
  value       = aws_dsql_cluster.this.arn
}

output "cluster_identifier" {
  description = "Aurora DSQL cluster identifier"
  value       = aws_dsql_cluster.this.identifier
}

output "cluster_endpoint" {
  description = "Aurora DSQL cluster endpoint (use VPC endpoint DNS for connection)"
  value       = aws_vpc_endpoint.dsql.dns_entry[0].dns_name
}

output "cluster_port" {
  description = "Aurora DSQL cluster port (PostgreSQL-compatible, port 5432)"
  value       = 5432
}

output "vpc_endpoint_dns" {
  description = "DNS name of VPC endpoint for DSQL connection"
  value       = aws_vpc_endpoint.dsql.dns_entry[0].dns_name
}

output "vpc_endpoint_service_name" {
  description = "VPC endpoint service name for DSQL"
  value       = aws_dsql_cluster.this.vpc_endpoint_service_name
}

output "security_group_id" {
  description = "Security group ID for DSQL VPC endpoint"
  value       = aws_security_group.dsql_endpoint.id
}

output "cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID (needed for IAM database authentication)"
  # DSQL uses identifier as resource ID for IAM auth (format: cluster-xxxxx)
  value = aws_dsql_cluster.this.identifier
}

output "kms_key_arn" {
  description = "KMS key ARN used for DSQL cluster encryption"
  value       = aws_kms_key.dsql.arn
}

output "dsql_host" {
  description = <<-EOT
    DSQL cluster host for connection (format: <cluster-id>.<service-suffix>.<region>.on.aws)
    
    This is an alternative hostname format provided by AWS for DSQL clusters.
    It can be used interchangeably with the VPC endpoint DNS from within the VPC.
    
    Example: vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws
    
    Note: This hostname still requires VPC access to resolve and connect.
    Use this when you need the DSQL-specific hostname format rather than the VPC endpoint DNS.
    
    For most use cases, prefer using `cluster_endpoint` (VPC endpoint DNS) which is
    more explicit about the VPC endpoint connection method.
  EOT
  # Extract service suffix from vpc_endpoint_service_name (e.g., com.amazonaws.us-east-1.dsql-fnh4 -> dsql-fnh4)
  # Then construct hostname as: <cluster-id>.<service-suffix>.<region>.on.aws
  value = "${aws_dsql_cluster.this.identifier}.${element(split(".", aws_dsql_cluster.this.vpc_endpoint_service_name), 3)}.${aws_dsql_cluster.this.region}.on.aws"
}

output "data_api_enabled" {
  description = "Whether RDS Data API is enabled for DSQL cluster"
  value       = var.enable_data_api
}

output "data_api_resource_arn" {
  description = "ARN of DSQL cluster for use with RDS Data API (if enabled). Note: DSQL may not support RDS Data API."
  value       = var.enable_data_api ? aws_dsql_cluster.this.arn : null
}

output "connection_instructions" {
  description = "Instructions for connecting to Aurora DSQL"
  value       = <<-EOT
Aurora DSQL Connection Instructions:

1. Generate authentication token using AWS SDK/CLI:
   aws dsql generate-db-auth-token --endpoint ${aws_vpc_endpoint.dsql.dns_entry[0].dns_name} --user admin

2. Connect using VPC endpoint DNS:
   Endpoint: ${aws_vpc_endpoint.dsql.dns_entry[0].dns_name}
   Port: 5432
   User: admin (or IAM database user)
   Password: <generated-token>

3. Connection string format:
   postgresql://admin:<token>@${aws_vpc_endpoint.dsql.dns_entry[0].dns_name}:5432/<database_name>

4. Note: DSQL uses token-based authentication (no master password).
   Create databases and schemas after connecting.

5. For IAM database authentication, ensure the Lambda has rds-db:connect permission.
   Resource ID: ${aws_dsql_cluster.this.identifier}

6. RDS Data API (if enabled):
   Use cluster ARN with aws rds-data execute-statement
   Resource ARN: ${aws_dsql_cluster.this.arn}
   Note: DSQL may not support RDS Data API. Verify compatibility before use.
EOT
}
