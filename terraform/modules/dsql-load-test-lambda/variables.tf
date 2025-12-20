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

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "architectures" {
  description = "Lambda architecture"
  type        = list(string)
  default     = ["arm64"]
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 1024
}

variable "timeout" {
  description = "Lambda timeout in seconds (15 minutes for long-running load tests)"
  type        = number
  default     = 900
}

variable "log_level" {
  description = "Logging level"
  type        = string
  default     = "info"
}

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "aurora_dsql_endpoint" {
  description = "Aurora DSQL cluster endpoint"
  type        = string
}

variable "aurora_dsql_port" {
  description = "Aurora DSQL cluster port"
  type        = number
  default     = 5432
}

variable "iam_database_user" {
  description = "IAM database username for Aurora DSQL"
  type        = string
}

variable "aurora_dsql_cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID for IAM permissions (format: cluster-xxxxx)"
  type        = string
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

variable "vpc_config" {
  description = "VPC configuration for Lambda (null if not in VPC)"
  type = object({
    security_group_ids = list(string)
    subnet_ids         = list(string)
  })
  default = null
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for Lambda (null = no limit, recommended: 1000 for load tests)"
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
