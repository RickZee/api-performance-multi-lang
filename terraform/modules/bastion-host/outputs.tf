output "instance_id" {
  description = "Bastion host instance ID"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Bastion host public IP address"
  value       = aws_instance.bastion.public_ip
}

output "private_ip" {
  description = "Bastion host private IP address"
  value       = aws_instance.bastion.private_ip
}

output "elastic_ip" {
  description = "Bastion host Elastic IP address (if allocated)"
  value       = var.allocate_elastic_ip ? aws_eip.bastion[0].public_ip : null
}

output "ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = var.ssh_public_key != "" ? "ssh -i ~/.ssh/${aws_key_pair.bastion[0].key_name}.pem ec2-user@${var.allocate_elastic_ip ? aws_eip.bastion[0].public_ip : aws_instance.bastion.public_ip}" : "Use SSM: aws ssm start-session --target ${aws_instance.bastion.id}"
}

output "ssm_command" {
  description = "SSM command to connect to bastion host"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.aws_region}"
}

output "iam_role_arn" {
  description = "ARN of the bastion host IAM role"
  value       = aws_iam_role.bastion.arn
}
