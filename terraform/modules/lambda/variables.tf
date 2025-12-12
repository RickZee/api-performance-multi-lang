variable "function_name" {
  description = "Lambda function name"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
}

variable "s3_key" {
  description = "S3 key (path) to the Lambda deployment package"
  type        = string
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
  default     = "bootstrap"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "provided.al2023"
}

variable "architectures" {
  description = "Lambda architecture"
  type        = list(string)
  default     = ["x86_64"]
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "log_level" {
  description = "Logging level"
  type        = string
  default     = "info"
}

variable "database_url" {
  description = "Database connection string"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aurora_endpoint" {
  description = "Aurora endpoint"
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = ""
}

variable "database_user" {
  description = "Database user"
  type        = string
  default     = ""
}

variable "database_password" {
  description = "Database password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vpc_config" {
  description = "VPC configuration for Lambda (null if not in VPC)"
  type = object({
    security_group_ids = list(string)
    subnet_ids         = list(string)
  })
  default = null
}

variable "api_name" {
  description = "API Gateway HTTP API name"
  type        = string
}

variable "api_description" {
  description = "API Gateway HTTP API description"
  type        = string
  default     = ""
}

variable "cors_config" {
  description = "CORS configuration for API Gateway"
  type = object({
    allow_origins = list(string)
    allow_methods = list(string)
    allow_headers = list(string)
    max_age       = number
  })
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "additional_environment_variables" {
  description = "Additional environment variables to add to the Lambda function"
  type        = map(string)
  default     = {}
}

