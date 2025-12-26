variable "cluster_name" {
  description = "Name of the MSK Serverless cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where MSK cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for MSK cluster (at least 2 in different AZs required)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "MSK Serverless requires at least 2 subnets in different availability zones."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

