variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the Aurora cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the Aurora subnet group"
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for security group rules"
  type        = string
}


variable "deletion_protection" {
  description = "Enable deletion protection for DSQL cluster"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
