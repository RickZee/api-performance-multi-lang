output "python_rest_pg_api_url" {
  description = "API Gateway HTTP API endpoint URL for Python REST (PostgreSQL)"
  value       = var.enable_python_lambda_pg ? module.python_rest_lambda_pg[0].api_url : null
}

output "python_rest_pg_function_name" {
  description = "Python REST Lambda function name (PostgreSQL)"
  value       = var.enable_python_lambda_pg ? module.python_rest_lambda_pg[0].function_name : null
}

output "python_rest_pg_function_arn" {
  description = "Python REST Lambda function ARN (PostgreSQL)"
  value       = var.enable_python_lambda_pg ? module.python_rest_lambda_pg[0].function_arn : null
}

output "python_rest_dsql_api_url" {
  description = "API Gateway HTTP API endpoint URL for Python REST DSQL"
  value       = var.enable_python_lambda_dsql ? module.python_rest_lambda_dsql[0].api_url : null
}

output "python_rest_dsql_function_name" {
  description = "Python REST DSQL Lambda function name"
  value       = var.enable_python_lambda_dsql ? module.python_rest_lambda_dsql[0].function_name : null
}

output "python_rest_dsql_function_arn" {
  description = "Python REST DSQL Lambda function ARN"
  value       = var.enable_python_lambda_dsql ? module.python_rest_lambda_dsql[0].function_arn : null
}

output "s3_bucket_name" {
  description = "S3 bucket name for Lambda deployments"
  value       = aws_s3_bucket.lambda_deployments.id
}

output "database_endpoint" {
  description = "Database endpoint (if created)"
  value       = var.enable_database ? module.database[0].endpoint : null
}

output "database_port" {
  description = "Database port (if created)"
  value       = var.enable_database ? module.database[0].port : null
}

output "lambda_security_group_id" {
  description = "Lambda security group ID (if VPC enabled)"
  value       = var.enable_vpc ? aws_security_group.lambda[0].id : null
}

output "database_security_group_id" {
  description = "Database security group ID (if database enabled)"
  value       = var.enable_database ? module.database[0].security_group_id : null
}

# Aurora Outputs
output "aurora_endpoint" {
  description = "Aurora cluster endpoint (writer)"
  value       = var.enable_aurora ? module.aurora[0].cluster_endpoint : null
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = var.enable_aurora ? module.aurora[0].cluster_reader_endpoint : null
}

output "aurora_port" {
  description = "Aurora cluster port"
  value       = var.enable_aurora ? module.aurora[0].cluster_port : null
}

output "aurora_connection_string" {
  description = "Aurora PostgreSQL connection string"
  value       = var.enable_aurora ? module.aurora[0].connection_string : null
  sensitive   = true
}

output "aurora_r2dbc_connection_string" {
  description = "Aurora R2DBC connection string for Spring Boot"
  value       = var.enable_aurora ? module.aurora[0].r2dbc_connection_string : null
  sensitive   = false
}

output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = var.enable_aurora ? module.aurora[0].security_group_id : null
}

# VPC Outputs
output "vpc_id" {
  description = "VPC ID (if Aurora enabled)"
  value       = var.enable_aurora ? module.vpc[0].vpc_id : null
}

output "vpc_cidr" {
  description = "VPC CIDR block (if Aurora enabled)"
  value       = var.enable_aurora ? module.vpc[0].vpc_cidr : null
}

output "private_subnet_ids" {
  description = "Private subnet IDs (if Aurora enabled)"
  value       = var.enable_aurora ? module.vpc[0].private_subnet_ids : null
}

output "public_subnet_ids" {
  description = "Public subnet IDs (if Aurora enabled)"
  value       = var.enable_aurora ? module.vpc[0].public_subnet_ids : null
}

# Aurora DSQL Outputs
output "aurora_dsql_endpoint" {
  description = "Aurora DSQL cluster endpoint (writer)"
  value       = var.enable_aurora_dsql_cluster ? module.aurora_dsql[0].cluster_endpoint : null
}

output "aurora_dsql_cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID (for IAM permissions)"
  value       = var.enable_aurora_dsql_cluster ? module.aurora_dsql[0].cluster_resource_id : null
}

output "aurora_dsql_port" {
  description = "Aurora DSQL cluster port"
  value       = var.enable_aurora_dsql_cluster ? module.aurora_dsql[0].cluster_port : null
}

output "aurora_dsql_security_group_id" {
  description = "Aurora DSQL security group ID"
  value       = var.enable_aurora_dsql_cluster ? module.aurora_dsql[0].security_group_id : null
}

output "aurora_dsql_host" {
  description = "Aurora DSQL host for connection (format: <cluster-id>.<service-suffix>.<region>.on.aws)"
  value       = var.enable_aurora_dsql_cluster ? module.aurora_dsql[0].dsql_host : null
}

# Terraform State Backend Outputs
output "terraform_state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = var.enable_terraform_state_backend ? aws_s3_bucket.terraform_state[0].id : null
}

# DynamoDB table output removed - using S3 native locking instead
# output "terraform_state_dynamodb_table_name" {
#   description = "DynamoDB table name for Terraform state locking"
#   value       = var.enable_terraform_state_backend ? aws_dynamodb_table.terraform_state_lock[0].name : null
# }

# DSQL Test Runner EC2 Outputs
# DSQL Test Runner Outputs - REMOVED (now using bastion host)
# Use bastion_host_instance_id and bastion_host_ssm_command instead

# Bastion Host Outputs
output "bastion_host_instance_id" {
  description = "Bastion host instance ID"
  value       = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? module.bastion_host[0].instance_id : null
}

output "bastion_host_public_ip" {
  description = "Bastion host public IP address"
  value       = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? module.bastion_host[0].public_ip : null
}

output "bastion_host_elastic_ip" {
  description = "Bastion host Elastic IP address (if allocated)"
  value       = var.enable_bastion_host && var.enable_aurora_dsql_cluster && var.bastion_allocate_elastic_ip ? module.bastion_host[0].elastic_ip : null
}

output "bastion_host_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? module.bastion_host[0].ssh_command : null
}

output "bastion_host_ssm_command" {
  description = "SSM command to connect to bastion host"
  value       = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? module.bastion_host[0].ssm_command : null
}

