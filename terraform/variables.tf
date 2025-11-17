variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "producer-api"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "database_url" {
  description = "Full database connection string (optional, used if provided)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aurora_endpoint" {
  description = "Aurora Serverless endpoint (optional, used if DATABASE_URL not provided)"
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Database name (optional, used with AuroraEndpoint)"
  type        = string
  default     = "car_entities"
}

variable "database_user" {
  description = "Database user (optional, used with AuroraEndpoint)"
  type        = string
  default     = "postgres"
}

variable "database_password" {
  description = "Database password (optional, used with AuroraEndpoint)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_level" {
  description = "Logging level"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error"
  }
}

variable "vpc_id" {
  description = "VPC ID for Aurora Serverless access (optional)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for Aurora Serverless access (optional)"
  type        = list(string)
  default     = []
}

variable "enable_database" {
  description = "Whether to create database infrastructure"
  type        = bool
  default     = false
}

variable "enable_vpc" {
  description = "Whether to enable VPC configuration"
  type        = bool
  default     = false
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Lambda deployments (will be created if not exists)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

