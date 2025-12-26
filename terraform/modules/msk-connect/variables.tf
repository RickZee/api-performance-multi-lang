variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "msk_cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
}

variable "msk_bootstrap_servers" {
  description = "Bootstrap servers for MSK cluster (IAM auth endpoint)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for MSK Connect"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for MSK Connect workers"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "connector_configuration" {
  description = "Connector configuration map (key-value pairs)"
  type        = map(string)
}

variable "connector_mcu_count" {
  description = "MCU count for connector (1 MCU = 1 vCPU, 4 GB memory)"
  type        = number
  default     = 1
}

variable "connector_min_workers" {
  description = "Minimum number of workers for autoscaling"
  type        = number
  default     = 1
}

variable "connector_max_workers" {
  description = "Maximum number of workers for autoscaling"
  type        = number
  default     = 2
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

