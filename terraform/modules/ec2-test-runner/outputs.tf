output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.test_runner.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.test_runner.private_ip
}

output "ssm_managed_instance_hint" {
  description = "Instance ID for SSM Session Manager (use with: aws ssm start-session --target <this-value>)"
  value       = aws_instance.test_runner.id
}

