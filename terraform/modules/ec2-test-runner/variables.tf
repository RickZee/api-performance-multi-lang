variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EC2 instance"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for the EC2 instance"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "iam_database_user" {
  description = "IAM database username for DSQL authentication"
  type        = string
}

variable "aurora_dsql_cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID for IAM authentication"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "dsql_kms_key_arn" {
  description = "KMS key ARN used for DSQL cluster encryption (required for EC2 to decrypt DSQL data)"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for downloading deployment packages"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
