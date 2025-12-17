output "ssm_endpoint_id" {
  description = "ID of the SSM VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

output "ssmmessages_endpoint_id" {
  description = "ID of the SSM Messages VPC endpoint"
  value       = aws_vpc_endpoint.ssmmessages.id
}

output "ec2messages_endpoint_id" {
  description = "ID of the EC2 Messages VPC endpoint"
  value       = aws_vpc_endpoint.ec2messages.id
}

output "security_group_id" {
  description = "Security group ID for SSM endpoints"
  value       = aws_security_group.ssm_endpoints.id
}
