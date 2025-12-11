variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the PrivateLink endpoint"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the VPC endpoint (should be private subnets)"
  type        = list(string)
}

variable "confluent_service_name" {
  description = "Confluent Cloud PrivateLink service name (from Confluent Console)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}


