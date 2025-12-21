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

variable "enable_aurora_dsql_cluster" {
  description = "Whether to create Aurora DSQL cluster (separate from regular Aurora)"
  type        = bool
  default     = false
}

variable "enable_dsql_data_api" {
  description = "Enable RDS Data API (HTTP endpoint) for DSQL cluster. Note: DSQL may not support RDS Data API."
  type        = bool
  default     = false
}

# Note: Aurora DSQL is serverless and uses ACU (Aurora Capacity Units) instead of instance classes
# DEPRECATED: aurora_dsql_instance_class is no longer used for DSQL (serverless uses ACU)
variable "aurora_dsql_instance_class" {
  description = "[DEPRECATED] Aurora DSQL is serverless and uses ACU instead. Use aurora_dsql_min_capacity and aurora_dsql_max_capacity instead."
  type        = string
  default     = null
}

variable "aurora_dsql_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACU) for DSQL serverless scaling. Default: 1 ACU (minimum for serverless)"
  type        = number
  default     = 1
}

variable "aurora_dsql_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACU) for DSQL serverless scaling. Default: 2 ACU (sufficient for dev)"
  type        = number
  default     = 2
}

variable "aurora_dsql_auto_pause" {
  description = "Whether to automatically pause DSQL database after inactivity (cost optimization for dev). Default: true"
  type        = bool
  default     = true
}

variable "aurora_dsql_seconds_until_auto_pause" {
  description = "Time in seconds before DSQL database automatically pauses (only used if auto_pause is true). Default: 300 (5 minutes)"
  type        = number
  default     = 300
}

variable "aurora_dsql_publicly_accessible" {
  description = "Make Aurora DSQL cluster publicly accessible"
  type        = bool
  default     = true
}

variable "aurora_dsql_database_name" {
  description = "Database name for Aurora DSQL cluster"
  type        = string
  default     = "car_entities"
}

variable "aurora_dsql_database_user" {
  description = "Database master username for Aurora DSQL (for initial setup, IAM users created separately)"
  type        = string
  default     = "postgres"
}

variable "aurora_dsql_database_password" {
  description = "Database master password for Aurora DSQL"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aurora_dsql_engine_version" {
  description = "Aurora DSQL engine version"
  type        = string
  default     = "15.14"
}

variable "enable_vpc" {
  description = "Whether to enable VPC configuration (for existing VPC)"
  type        = bool
  default     = false
}

variable "aurora_instance_class" {
  description = "Aurora instance class. Defaults: db.t3.small for dev, db.r5.large for test (can be overridden)"
  type        = string
  default     = null
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
  description = "Lambda timeout in seconds (default: 30 to handle event processing)"
  type        = number
  default     = 30
}

variable "enable_python_lambda_pg" {
  description = "Enable Python Lambda function for PostgreSQL (regular Aurora)"
  type        = bool
  default     = false
}

variable "enable_python_lambda_dsql" {
  description = "Enable Python Lambda function with DSQL support (separate from regular Python Lambda)"
  type        = bool
  default     = false
}

variable "enable_dsql_load_test_lambda" {
  description = "Enable DSQL load test Lambda function (standalone load testing, separate from producer API)"
  type        = bool
  default     = false
}

variable "dsql_load_test_lambda_memory_size" {
  description = "Memory size for DSQL load test Lambda in MB (default: 1024 for load testing)"
  type        = number
  default     = 1024
}

variable "dsql_load_test_lambda_timeout" {
  description = "Timeout for DSQL load test Lambda in seconds (default: 300 = 5 minutes)"
  type        = number
  default     = 300
}

variable "dsql_load_test_lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for DSQL load test Lambda (null = no limit, recommended: 1000 for load tests)"
  type        = number
  default     = null
}

variable "enable_rds_proxy" {
  description = "Enable RDS Proxy for connection pooling (recommended for high Lambda parallelism)"
  type        = bool
  default     = true
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
  description = "Aurora backup retention period in days. Defaults: 1 for dev, 3 for test (set via environment variable)"
  type        = number
  default     = null
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch Logs retention period in days. Defaults: 1 for dev, 3 for test (set via environment variable)"
  type        = number
  default     = null
  validation {
    condition     = var.cloudwatch_logs_retention_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch Logs retention must be one of the valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653"
  }
}

variable "environment" {
  description = "Environment name (dev, test) - 'dev' uses absolute minimum infrastructure, 'test' uses larger RDS instance (db.r5.large)"
  type        = string
  default     = "test"
  validation {
    condition     = contains(["dev", "test"], var.environment)
    error_message = "Environment must be one of: dev, test"
  }
}

variable "enable_aurora_dsql" {
  description = "Whether to use Aurora DSQL with IAM authentication (alternative to regular Aurora)"
  type        = bool
  default     = false
}

variable "aurora_dsql_endpoint" {
  description = "Aurora DSQL cluster endpoint (required if enable_aurora_dsql is true)"
  type        = string
  default     = ""
}

variable "aurora_dsql_port" {
  description = "Aurora DSQL cluster port (default: 5432)"
  type        = number
  default     = 5432
}

variable "iam_database_user" {
  description = "IAM database username for Aurora DSQL authentication (required if enable_aurora_dsql is true)"
  type        = string
  default     = ""
}

variable "aurora_dsql_cluster_resource_id" {
  description = "Aurora DSQL cluster resource ID for IAM permissions (format: cluster-xxxxx, required if enable_aurora_dsql is true)"
  type        = string
  default     = ""
}

variable "enable_dsql_test_runner_ec2" {
  description = "Whether to create an EC2 test runner instance for DSQL connector testing (SSM access only, in private subnet)"
  type        = bool
  default     = false
}

variable "dsql_test_runner_instance_type" {
  description = "EC2 instance type for DSQL test runner"
  type        = string
  default     = "t3.small"
}

variable "enable_bastion_host" {
  description = "Enable bastion host for database access"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_public_key" {
  description = "SSH public key for bastion host access (optional, can use SSM instead)"
  type        = string
  default     = ""
}

variable "bastion_ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_allocate_elastic_ip" {
  description = "Whether to allocate an Elastic IP for the bastion host"
  type        = bool
  default     = false
}

variable "aurora_auto_stop_admin_email" {
  description = <<-EOT
    Admin email address for Aurora auto-stop notifications.
    
    When provided, an email will be sent when the Aurora cluster is automatically stopped due to inactivity.
    Leave empty (default) to disable email notifications.
    
    Note: AWS SNS requires email confirmation. After setting this variable and running terraform apply,
    you will receive a confirmation email at the provided address. You must click the confirmation link
    before notifications will be sent.
  EOT
  type        = string
  default     = ""
}
