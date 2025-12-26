output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = aws_instance.nat.id
}

output "nat_instance_private_ip" {
  description = "Private IP address of the NAT instance"
  value       = aws_instance.nat.private_ip
}

output "nat_instance_public_ip" {
  description = "Public IP address (Elastic IP) of the NAT instance"
  value       = aws_eip.nat_instance.public_ip
}

output "elastic_ip_allocation_id" {
  description = "Elastic IP allocation ID"
  value       = aws_eip.nat_instance.id
}

output "security_group_id" {
  description = "Security group ID for NAT instance"
  value       = aws_security_group.nat_instance.id
}

