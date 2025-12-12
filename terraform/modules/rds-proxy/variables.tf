variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for RDS Proxy"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS Proxy (must be in at least 2 AZs)"
  type        = list(string)
}

variable "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  type        = string
}

variable "aurora_security_group_id" {
  description = "Security group ID for Aurora cluster"
  type        = string
}

variable "lambda_security_group_ids" {
  description = "List of Lambda security group IDs that will connect to RDS Proxy"
  type        = list(string)
  default     = []
}

variable "database_user" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "max_connections_percent" {
  description = "Maximum percentage of database connections that RDS Proxy can use (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.max_connections_percent >= 1 && var.max_connections_percent <= 100
    error_message = "max_connections_percent must be between 1 and 100"
  }
}

variable "max_idle_connections_percent" {
  description = "Maximum percentage of idle connections that RDS Proxy can maintain (0-100)"
  type        = number
  default     = 50
  validation {
    condition     = var.max_idle_connections_percent >= 0 && var.max_idle_connections_percent <= 100
    error_message = "max_idle_connections_percent must be between 0 and 100"
  }
}

variable "connection_borrow_timeout" {
  description = "Maximum time (in seconds) to wait for a connection from the pool"
  type        = number
  default     = 120
}

variable "enable_debug_logging" {
  description = "Enable debug logging for RDS Proxy"
  type        = bool
  default     = false
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

