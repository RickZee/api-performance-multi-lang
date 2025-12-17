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

variable "api_gateway_id" {
  description = "API Gateway ID to monitor for invocations"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "inactivity_hours" {
  description = "Number of hours of inactivity before stopping Aurora"
  type        = number
  default     = 3
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

variable "admin_email" {
  description = "Admin email address for Aurora auto-stop notifications (optional, leave empty to disable notifications)"
  type        = string
  default     = ""

  validation {
    condition     = var.admin_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address or empty string to disable notifications."
  }
}
