provider "aws" {
  region = var.aws_region
}

# S3 bucket for Lambda deployments
resource "aws_s3_bucket" "lambda_deployments" {
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-lambda-deployments-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-lambda-deployments"
    }
  )
}

resource "aws_s3_bucket_versioning" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.environment == "prod" ? 30 : 14
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  count  = var.enable_terraform_state_backend ? 1 : 0
  bucket = var.terraform_state_bucket_name

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-terraform-state"
      Description = "Terraform state storage"
    }
  )
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  count  = var.enable_terraform_state_backend ? 1 : 0
  bucket = aws_s3_bucket.terraform_state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  count  = var.enable_terraform_state_backend ? 1 : 0
  bucket = aws_s3_bucket.terraform_state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  count  = var.enable_terraform_state_backend ? 1 : 0
  bucket = aws_s3_bucket.terraform_state[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  count  = var.enable_terraform_state_backend ? 1 : 0
  bucket = aws_s3_bucket.terraform_state[0].id

  rule {
    id     = "delete-old-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.environment == "prod" ? 90 : 30
    }
  }
}

# DynamoDB table for Terraform state locking (DEPRECATED - using S3 native locking instead)
# Terraform 1.10+ supports native S3 state locking via use_lockfile parameter
# This eliminates the need for DynamoDB. Keeping commented for reference.
# resource "aws_dynamodb_table" "terraform_state_lock" {
#   count        = var.enable_terraform_state_backend ? 1 : 0
#   name         = var.terraform_state_dynamodb_table_name != "" ? var.terraform_state_dynamodb_table_name : "${var.project_name}-terraform-state-lock"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
#
#   tags = merge(
#     local.common_tags,
#     {
#       Name        = "${var.project_name}-terraform-state-lock"
#       Description = "Terraform state locking"
#     }
#   )
# }

# Security group for Lambda functions (if VPC enabled)
resource "aws_security_group" "lambda" {
  count = var.enable_vpc || var.enable_aurora ? 1 : 0

  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda functions to access Aurora"
  vpc_id      = var.enable_aurora ? module.vpc[0].vpc_id : var.vpc_id

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound to Aurora (IPv4)"
  }

  # IPv6 egress for Aurora access (if IPv6 is enabled)
  dynamic "egress" {
    for_each = var.enable_aurora && try(module.vpc[0].vpc_ipv6_cidr_block != null, false) ? [1] : []
    content {
      from_port        = 5432
      to_port          = 5432
      protocol         = "tcp"
      ipv6_cidr_blocks = ["::/0"]
      description      = "Allow outbound to Aurora (IPv6)"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-lambda-sg"
    }
  )
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# VPC Module - Create new VPC for Aurora infrastructure
module "vpc" {
  count  = var.enable_aurora ? 1 : 0
  source = "./modules/vpc"

  project_name      = var.project_name
  enable_ipv6       = var.enable_ipv6
  enable_nat_gateway = var.enable_nat_gateway
  tags              = local.common_tags
}

# Aurora PostgreSQL Module
# 
# Public Internet Access Configuration:
# - When aurora_publicly_accessible = true and confluent_cloud_cidrs is provided:
#   Security group restricts access to Confluent Cloud IP ranges only (recommended)
# - When aurora_publicly_accessible = true and confluent_cloud_cidrs is empty:
#   Security group allows access from all IPs (0.0.0.0/0) - use with caution
# - When aurora_publicly_accessible = false:
#   Aurora is only accessible from within the VPC (private access)
#
# For production, consider using AWS PrivateLink instead of public access.
# See: terraform/PUBLIC_ACCESS_SETUP.md for setup guide.
module "aurora" {
  count  = var.enable_aurora ? 1 : 0
  source = "./modules/aurora"

  project_name      = var.project_name
  vpc_id            = module.vpc[0].vpc_id
  # For public access, use ONLY public subnets to ensure instance is in public subnet
  # AWS RDS requires at least 2 subnets in different AZs - we have 2 public subnets which is sufficient
  # Using only public subnets ensures the instance is actually publicly accessible
  subnet_ids        = var.aurora_publicly_accessible ? module.vpc[0].public_subnet_ids : module.vpc[0].private_subnet_ids
  database_name     = var.database_name
  database_user     = var.database_user
  database_password = var.database_password

  # Aurora configuration
  instance_class        = var.aurora_instance_class
  publicly_accessible   = var.aurora_publicly_accessible
  confluent_cloud_cidrs = local.confluent_cloud_cidrs
  allowed_cidr_blocks   = var.aurora_allowed_cidr_blocks
  enable_ipv6           = var.enable_ipv6
  # Backup retention: use provided value or environment-based default (3 days for dev/staging, 7 for prod)
  backup_retention_period = var.backup_retention_period != null ? var.backup_retention_period : (local.is_production ? 7 : 3)
  additional_security_group_ids = []

  tags = local.common_tags
}

# Local values for database connection string
locals {
  has_database_url = var.database_url != ""
  has_vpc_config   = var.enable_vpc && var.vpc_id != "" && length(var.subnet_ids) > 0

  # Use Aurora endpoint if available, otherwise use provided endpoint or URL
  aurora_endpoint = var.enable_aurora ? try(module.aurora[0].cluster_endpoint, var.aurora_endpoint) : var.aurora_endpoint

  database_url = local.has_database_url ? var.database_url : (
    local.aurora_endpoint != "" ? "postgresql://${var.database_user}:${var.database_password}@${local.aurora_endpoint}:5432/${var.database_name}" : ""
  )

  # Confluent Cloud IP ranges for public internet access
  # These IP ranges are used to restrict Aurora security group access when using public internet access.
  # To find current Confluent Cloud egress IP ranges:
  # 1. Check documentation: https://docs.confluent.io/cloud/current/networking/ip-ranges.html
  # 2. Use Confluent CLI: confluent network egress-ip list
  # 3. Use helper script: terraform/scripts/get-confluent-cloud-ips.sh
  # 4. Contact Confluent support for region-specific IP ranges
  #
  # Note: If confluent_cloud_cidrs is empty and aurora_publicly_accessible is true,
  #       Aurora will be accessible from all IPs (0.0.0.0/0) - not recommended for production.
  confluent_cloud_cidrs = var.confluent_cloud_cidrs

  # Common tags for all AWS resources - includes "Project=Flink POC"
  # Project tag is placed last to ensure it's always "Flink POC" and not overridden
  common_tags = merge(
    var.tags,
    {
      Project     = "Flink POC"
      Environment = var.environment
    }
  )

  # Environment-based cost optimization defaults
  # Production uses more conservative settings, dev/staging use cost-optimized defaults
  is_production = var.environment == "prod"
}

# Python REST Lambda module (optional - disabled by default)
module "python_rest_lambda" {
  count  = var.enable_python_lambda ? 1 : 0
  source = "./modules/lambda"

  function_name     = "${var.project_name}-python-rest-lambda"
  s3_bucket         = aws_s3_bucket.lambda_deployments.id
  s3_key            = "python-rest/lambda-deployment.zip"
  handler           = "lambda_handler.handler"
  runtime           = "python3.11"
  architectures     = ["x86_64"]
  memory_size       = var.lambda_memory_size
  timeout           = var.lambda_timeout
  log_level         = var.log_level
  cloudwatch_logs_retention_days = var.cloudwatch_logs_retention_days
  database_url      = local.database_url
  aurora_endpoint   = local.aurora_endpoint
  database_name     = var.database_name
  database_user     = var.database_user
  database_password = var.database_password

  vpc_config = local.has_vpc_config ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = var.subnet_ids
    } : (var.enable_aurora ? {
      security_group_ids = [module.aurora[0].security_group_id]
      subnet_ids         = module.vpc[0].private_subnet_ids
  } : null)

  api_name        = "${var.project_name}-python-rest-http-api"
  api_description = "HTTP API for Producer API Python REST Lambda"
  cors_config = {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

# Aurora Auto-Stop Lambda (only for dev/staging environments)
# Monitors API Gateway invocations and stops Aurora if no activity for 3 hours
module "aurora_auto_stop" {
  count  = var.enable_aurora && !local.is_production && var.enable_python_lambda ? 1 : 0
  source = "./modules/aurora-auto-stop"

  function_name      = "${var.project_name}-aurora-auto-stop"
  aurora_cluster_id  = module.aurora[0].cluster_id
  aurora_cluster_arn = module.aurora[0].cluster_arn
  api_gateway_id     = module.python_rest_lambda[0].api_id
  aws_region         = var.aws_region
  inactivity_hours   = 3
  cloudwatch_logs_retention_days = var.cloudwatch_logs_retention_days

  tags = local.common_tags
}

# Optional database module
module "database" {
  count  = var.enable_database ? 1 : 0
  source = "./modules/database"

  project_name      = var.project_name
  database_name     = var.database_name
  database_user     = var.database_user
  database_password = var.database_password
  vpc_id            = var.vpc_id
  subnet_ids        = var.subnet_ids

  tags = local.common_tags
}

