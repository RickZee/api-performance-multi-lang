variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where NAT instance will be deployed"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID where NAT instance will be deployed"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets that will use this NAT instance"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for NAT instance. Recommended: t4g.nano or t4g.small for cost savings"
  type        = string
  default     = "t4g.nano"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

