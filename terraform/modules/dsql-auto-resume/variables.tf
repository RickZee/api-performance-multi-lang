variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "dsql_cluster_resource_id" {
  description = "DSQL cluster resource ID (format: cluster-xxxxx)"
  type        = string
}

variable "dsql_cluster_arn" {
  description = "DSQL cluster ARN"
  type        = string
}

variable "dsql_target_min_capacity" {
  description = "Target minimum ACU capacity to scale up to when resuming (typically 1 ACU)"
  type        = number
  default     = 1
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
