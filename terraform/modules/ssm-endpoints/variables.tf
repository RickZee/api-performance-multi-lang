variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the SSM endpoints"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the SSM endpoints (private subnets)"
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

