output "vpc_endpoint_id" {
  description = "VPC endpoint ID"
  value       = aws_vpc_endpoint.confluent.id
}

output "vpc_endpoint_dns_name" {
  description = "VPC endpoint DNS name"
  value       = aws_vpc_endpoint.confluent.dns_entry[0].dns_name
}

output "security_group_id" {
  description = "Security group ID for Confluent PrivateLink"
  value       = aws_security_group.confluent_privatelink.id
}



