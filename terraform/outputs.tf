output "grpc_api_url" {
  description = "API Gateway HTTP API endpoint URL for gRPC"
  value       = module.grpc_lambda.api_url
}

output "rest_api_url" {
  description = "API Gateway HTTP API endpoint URL for REST"
  value       = module.rest_lambda.api_url
}

output "grpc_function_name" {
  description = "gRPC Lambda function name"
  value       = module.grpc_lambda.function_name
}

output "rest_function_name" {
  description = "REST Lambda function name"
  value       = module.rest_lambda.function_name
}

output "grpc_function_arn" {
  description = "gRPC Lambda function ARN"
  value       = module.grpc_lambda.function_arn
}

output "rest_function_arn" {
  description = "REST Lambda function ARN"
  value       = module.rest_lambda.function_arn
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

