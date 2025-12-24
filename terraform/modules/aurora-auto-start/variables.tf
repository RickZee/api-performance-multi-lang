variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  type        = string
}

variable "aurora_cluster_arn" {
  description = "Aurora cluster ARN"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
