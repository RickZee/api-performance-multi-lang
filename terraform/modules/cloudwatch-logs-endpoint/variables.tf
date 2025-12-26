variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the CloudWatch Logs endpoint"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the CloudWatch Logs endpoint (private subnets)"
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

