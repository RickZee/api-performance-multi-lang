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

variable "flink_app_jar_key" {
  description = "S3 key for the Flink application JAR file"
  type        = string
}

variable "parallelism" {
  description = "Initial parallelism for Flink application"
  type        = number
  default     = 1
}

variable "parallelism_per_kpu" {
  description = "Parallelism per KPU (Kinesis Processing Unit)"
  type        = number
  default     = 1
}

variable "enable_glue_schema_registry" {
  description = "Enable Glue Schema Registry integration"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "vpc_id" {
  description = "VPC ID for Flink application"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for Flink application"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for Flink application"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

