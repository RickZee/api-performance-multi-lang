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
  default     = 1
}

variable "additional_environment_variables" {
  description = "Additional environment variables to add to the Lambda function"
  type        = map(string)
  default     = {}
}

variable "aurora_dsql_endpoint" {
  description = "Aurora DSQL cluster endpoint"
  type        = string
  default     = ""
}

variable "aurora_dsql_port" {
  description = "Aurora DSQL cluster port"
  type        = number
  default     = 5432
}

variable "iam_database_user" {
  description = "IAM database username for Aurora DSQL"
  type        = string
  default     = ""
}

variable "enable_aurora_dsql" {
  description = "Whether to enable Aurora DSQL configuration"
  type        = bool
  default     = false
}

variable "aurora_dsql_cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID for IAM permissions (format: cluster-xxxxx)"
  type        = string
  default     = ""
}

variable "dsql_host" {
  description = "Aurora DSQL host for connection (format: <cluster-id>.<service-suffix>.<region>.on.aws)"
  type        = string
  default     = ""
}

variable "dsql_kms_key_arn" {
  description = "ARN of the KMS key used for DSQL encryption (required for Lambda to decrypt DSQL connections)"
  type        = string
  default     = ""
}

variable "enable_dlq" {
  description = "Enable Dead Letter Queue for failed Lambda invocations"
  type        = bool
  default     = true
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for DLQ in seconds (default: 1209600 = 14 days)"
  type        = number
  default     = 1209600
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for Lambda (null = no limit)"
  type        = number
  default     = null
}

variable "db_pool_max_size" {
  description = "Maximum database connection pool size (PostgreSQL variant only)"
  type        = number
  default     = 10
}

variable "db_pool_min_size" {
  description = "Minimum database connection pool size (PostgreSQL variant only)"
  type        = number
  default     = 1
}

variable "max_bulk_events" {
  description = "Maximum number of events allowed in bulk request"
  type        = number
  default     = 100
}
