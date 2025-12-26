output "cluster_arn" {
  description = "ARN of the MSK Serverless cluster"
  value       = aws_msk_serverless_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the MSK Serverless cluster"
  value       = aws_msk_serverless_cluster.this.cluster_name
}

output "bootstrap_brokers" {
  description = "Bootstrap broker addresses for the MSK cluster (deprecated - use bootstrap_brokers_sasl_iam)"
  value       = null
}

output "bootstrap_brokers_sasl_iam" {
  description = "Bootstrap broker addresses for IAM authentication (port 9098)"
  value       = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
}

output "security_group_id" {
  description = "Security group ID for MSK cluster"
  value       = aws_security_group.msk.id
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy for MSK access"
  value       = aws_iam_policy.msk_access.arn
}

output "connection_instructions" {
  description = "Instructions for connecting to MSK cluster"
  value = <<-EOT
MSK Serverless cluster is configured with IAM authentication.

Bootstrap Brokers (IAM): ${aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam}

Consumer/Producer Configuration:
- bootstrap.servers: ${aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam}
- security.protocol: SASL_SSL
- sasl.mechanism: AWS_MSK_IAM
- sasl.jaas.config: software.amazon.msk.auth.iam.IAMLoginModule required;
- sasl.client.callback.handler.class: software.amazon.msk.auth.iam.IAMClientCallbackHandler

IAM Policy ARN: ${aws_iam_policy.msk_access.arn}
Attach this policy to IAM roles/users that need MSK access.

For Python consumers, use: aws-msk-iam-sasl-signer-python library
EOT
}

