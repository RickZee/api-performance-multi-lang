output "cloudwatch_logs_endpoint_id" {
  description = "ID of the CloudWatch Logs VPC endpoint"
  value       = aws_vpc_endpoint.cloudwatch_logs.id
}

output "security_group_id" {
  description = "Security group ID for CloudWatch Logs endpoint"
  value       = aws_security_group.cloudwatch_logs_endpoint.id
}

