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

variable "api_gateway_id" {
  description = "API Gateway ID to monitor for invocations"
  type        = string
  default     = ""
}

variable "inactivity_hours" {
  description = "Number of hours of inactivity before scaling down DSQL"
  type        = number
  default     = 3
}

variable "dsql_min_capacity" {
  description = "Minimum ACU capacity to scale down to when inactive (0 = pause, 1 = minimum running)"
  type        = number
  default     = 0
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

variable "admin_email" {
  description = "Admin email address for DSQL auto-pause notifications (optional, leave empty to disable notifications)"
  type        = string
  default     = ""

  validation {
    condition     = var.admin_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address or empty string to disable notifications."
  }
}
