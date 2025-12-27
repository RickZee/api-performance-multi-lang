output "application_arn" {
  description = "ARN of the Flink application"
  value       = aws_kinesisanalyticsv2_application.flink_app.arn
}

output "application_name" {
  description = "Name of the Flink application"
  value       = aws_kinesisanalyticsv2_application.flink_app.name
}

output "s3_bucket_name" {
  description = "S3 bucket name for Flink application artifacts"
  value       = aws_s3_bucket.flink_apps.id
}

output "security_group_id" {
  description = "Security group ID for Flink application"
  value       = var.vpc_id != null ? aws_security_group.flink_app[0].id : null
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Flink application"
  value       = aws_iam_role.flink_app.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name for Flink application"
  value       = aws_cloudwatch_log_group.flink_app.name
}

