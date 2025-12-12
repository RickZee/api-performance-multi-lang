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

variable "enable_aurora" {
  description = "Whether to create Aurora PostgreSQL infrastructure"
  type        = bool
  default     = true
}

variable "enable_vpc" {
  description = "Whether to enable VPC configuration (for existing VPC)"
  type        = bool
  default     = false
}

variable "aurora_instance_class" {
  description = "Aurora instance class (cost-optimized default: db.t3.small)"
  type        = string
  default     = "db.t3.small"
}

variable "aurora_publicly_accessible" {
  description = "Make Aurora publicly accessible for Confluent Cloud"
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 on VPC and subnets. With IPv6, NAT Gateway is not needed for outbound internet access."
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (IPv4). Not needed if enable_ipv6 is true."
  type        = bool
  default     = false
}

variable "aurora_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Aurora (default: 0.0.0.0/0 for public access)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "confluent_cloud_cidrs" {
  description = <<-EOT
    CIDR blocks for Confluent Cloud egress IP ranges (optional, for security group).
    
    When aurora_publicly_accessible = true and this variable is provided:
    - Security group will restrict access to only these Confluent Cloud IP ranges (recommended)
    - Provides better security than allowing all IPs (0.0.0.0/0)
    
    When aurora_publicly_accessible = true and this variable is empty:
    - Security group will use aurora_allowed_cidr_blocks (defaults to 0.0.0.0/0)
    - Aurora will be accessible from all IPs - not recommended for production
    
    To find current Confluent Cloud egress IP ranges:
    1. Check documentation: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
    2. Use Confluent CLI: confluent network egress-ip list
    3. Use helper script: terraform/scripts/get-confluent-cloud-ips.sh
    4. Contact Confluent support for region-specific IP ranges
    
    Example:
      confluent_cloud_cidrs = ["13.57.0.0/16", "52.0.0.0/16"]
    
    Note: IP ranges may change over time. Update this configuration periodically.
    For production, consider using AWS PrivateLink instead of public access.
  EOT
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.confluent_cloud_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All confluent_cloud_cidrs must be valid CIDR blocks (e.g., 13.57.0.0/16)."
  }
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB (cost-optimized default: 256)"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds (cost-optimized default: 15)"
  type        = number
  default     = 15
}

variable "enable_python_lambda" {
  description = "Enable Python Lambda function"
  type        = bool
  default     = false
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

variable "terraform_state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "flink-poc-terraform-state"
}

variable "terraform_state_dynamodb_table_name" {
  description = "DynamoDB table name for Terraform state locking (DEPRECATED - using S3 native locking instead)"
  type        = string
  default     = ""
}

variable "enable_terraform_state_backend" {
  description = "Whether to create S3 bucket for Terraform state backend (uses S3 native locking, no DynamoDB required)"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Aurora backup retention period in days. Defaults: 3 for dev/staging, 7 for prod (set via environment variable)"
  type        = number
  default     = null
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days (cost-optimized default: 2)"
  type        = number
  default     = 2
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch Logs retention must be one of the valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) - used for cost optimization defaults"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

