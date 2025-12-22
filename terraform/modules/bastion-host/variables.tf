variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the bastion host"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the bastion host"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (keep small, not used for load tests)"
  type        = string
  default     = "t4g.nano"
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
  description = "KMS key ARN used for DSQL cluster encryption"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for read access (to download deployment packages)"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key for bastion host access (optional, can use SSM instead)"
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allocate_elastic_ip" {
  description = "Whether to allocate an Elastic IP for the bastion host"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
