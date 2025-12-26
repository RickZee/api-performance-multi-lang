output "connector_arn" {
  description = "ARN of the MSK Connect connector"
  value       = aws_mskconnect_connector.postgres_cdc.arn
}

output "connector_name" {
  description = "Name of the MSK Connect connector"
  value       = aws_mskconnect_connector.postgres_cdc.name
}

output "custom_plugin_arn" {
  description = "ARN of the custom plugin"
  value       = aws_mskconnect_custom_plugin.debezium_postgres.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name for plugin artifacts"
  value       = aws_s3_bucket.msk_connect_plugins.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for MSK Connect"
  value       = aws_iam_role.msk_connect.arn
}

output "security_group_id" {
  description = "Security group ID for MSK Connect"
  value       = aws_security_group.msk_connect.id
}

output "log_group_name" {
  description = "CloudWatch Log Group name for MSK Connect"
  value       = aws_cloudwatch_log_group.msk_connect.name
}

