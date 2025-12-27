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
      noncurrent_days = local.is_test ? 30 : 7 # 30 days for test, 7 days for dev
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
  count = var.enable_vpc || var.enable_aurora || var.enable_aurora_dsql_cluster ? 1 : 0

  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda functions to access Aurora"
  vpc_id      = (var.enable_aurora || var.enable_aurora_dsql_cluster) ? module.vpc[0].vpc_id : var.vpc_id

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound to Aurora (IPv4)"
  }

  # IPv6 egress for Aurora access (if IPv6 is enabled)
  dynamic "egress" {
    for_each = (var.enable_aurora || var.enable_aurora_dsql_cluster) && try(module.vpc[0].vpc_ipv6_cidr_block != null, false) ? [1] : []
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

# VPC Module - Create new VPC for Aurora infrastructure (or DSQL)
module "vpc" {
  count  = var.enable_aurora || var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/vpc"

  project_name       = var.project_name
  enable_ipv6        = var.enable_ipv6
  enable_nat_gateway = var.enable_nat_gateway
  tags               = local.common_tags
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

  project_name = var.project_name
  vpc_id       = module.vpc[0].vpc_id
  # For public access, use ONLY public subnets to ensure instance is in public subnet
  # AWS RDS requires at least 2 subnets in different AZs - we have 2 public subnets which is sufficient
  # Using only public subnets ensures the instance is actually publicly accessible
  subnet_ids        = var.aurora_publicly_accessible ? module.vpc[0].public_subnet_ids : module.vpc[0].private_subnet_ids
  database_name     = var.database_name
  database_user     = var.database_user
  database_password = var.database_password

  # Aurora configuration
  instance_class        = local.aurora_instance_class
  publicly_accessible   = var.aurora_publicly_accessible
  confluent_cloud_cidrs = local.confluent_cloud_cidrs
  allowed_cidr_blocks   = var.aurora_allowed_cidr_blocks
  enable_ipv6           = var.enable_ipv6
  # Backup retention: use provided value or environment-based default (1 day for dev, 3 days for test)
  backup_retention_period       = local.backup_retention
  additional_security_group_ids = []

  tags = local.common_tags
}

# RDS Proxy Module (enables connection pooling for high Lambda parallelism)
# Disabled for dev environment to minimize infrastructure, enabled for test
module "rds_proxy" {
  count  = var.enable_aurora && var.enable_python_lambda_pg && var.enable_rds_proxy && local.is_test ? 1 : 0
  source = "./modules/rds-proxy"

  project_name                   = var.project_name
  vpc_id                         = module.vpc[0].vpc_id
  subnet_ids                     = module.vpc[0].private_subnet_ids
  aurora_cluster_id              = module.aurora[0].cluster_id
  aurora_security_group_id       = module.aurora[0].security_group_id
  lambda_security_group_ids      = var.enable_aurora ? [aws_security_group.lambda[0].id] : []
  database_user                  = var.database_user
  database_password              = var.database_password
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  # Connection pool settings: Use 80% of max connections to leave headroom for admin connections
  max_connections_percent      = 80
  max_idle_connections_percent = 50
  connection_borrow_timeout    = 120

  tags = local.common_tags
}

# Security group rule: Allow RDS Proxy to access Aurora
# Only created if RDS Proxy module is actually created (test environment)
resource "aws_security_group_rule" "aurora_from_rds_proxy" {
  count = var.enable_aurora && var.enable_python_lambda_pg && var.enable_rds_proxy && local.is_test ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.rds_proxy[0].security_group_id
  security_group_id        = module.aurora[0].security_group_id
  description              = "Allow RDS Proxy to access Aurora PostgreSQL"
}

# Aurora DSQL Cluster Module (separate from regular Aurora PostgreSQL)
# Aurora DSQL is a brand new serverless, distributed SQL database (released May 2025)
module "aurora_dsql" {
  count  = var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/aurora-dsql"

  project_name        = var.project_name
  vpc_id              = module.vpc[0].vpc_id
  vpc_cidr_block      = module.vpc[0].vpc_cidr
  subnet_ids          = module.vpc[0].private_subnet_ids # DSQL uses VPC endpoints, always use private subnets
  deletion_protection = false                            # Set to true for production
  enable_data_api     = var.enable_dsql_data_api

  tags = local.common_tags
}

# Local values for database connection string
locals {
  has_database_url = var.database_url != ""
  has_vpc_config   = var.enable_vpc && var.vpc_id != "" && length(var.subnet_ids) > 0

  # Use Aurora endpoint if available, otherwise use provided endpoint or URL
  aurora_endpoint = var.enable_aurora ? try(module.aurora[0].cluster_endpoint, var.aurora_endpoint) : var.aurora_endpoint

  # Use RDS Proxy endpoint if available (for connection pooling), otherwise use Aurora endpoint
  rds_proxy_endpoint = var.enable_aurora && var.enable_python_lambda_pg && var.enable_rds_proxy ? try(module.rds_proxy[0].proxy_endpoint, null) : null
  database_endpoint  = local.rds_proxy_endpoint != null ? local.rds_proxy_endpoint : local.aurora_endpoint

  database_url = local.has_database_url ? var.database_url : (
    local.database_endpoint != "" ? "postgresql://${var.database_user}:${var.database_password}@${local.database_endpoint}:5432/${var.database_name}" : ""
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

  # Environment-based configuration
  # - dev: Absolute minimum infrastructure (1 day logs, 1 day backups, no RDS Proxy, db.t3.small)
  # - test: Standard testing setup (1 day logs, 3 days backups, RDS Proxy enabled, db.r5.large)
  is_dev  = var.environment == "dev"
  is_test = var.environment == "test"

  # CloudWatch Logs retention: 1 day for all environments
  cloudwatch_logs_retention = var.cloudwatch_logs_retention_days != null ? var.cloudwatch_logs_retention_days : 1

  # Backup retention: 1 day for dev, 3 days for test
  backup_retention = var.backup_retention_period != null ? var.backup_retention_period : (
    local.is_dev ? 1 : 3
  )

  # Aurora instance class: db.t4g.medium for dev (ARM-based for cost savings), db.r5.large for test
  # Note: Can be overridden in terraform.tfvars
  # db.t4g.medium is the smallest ARM instance supported for PostgreSQL 15.14 (~20% cheaper than x86 db.t3.medium)
  # db.t4g.small is NOT supported for Aurora PostgreSQL 15.14
  aurora_instance_class = var.aurora_instance_class != null ? var.aurora_instance_class : (
    local.is_dev ? "db.t4g.medium" : "db.r5.large"
  )
}

# Aurora Auto-Start Lambda (enabled for test and dev environments)
# Starts Aurora cluster when invoked by API Lambda on connection failure
# Defined before Python Lambda so it can be referenced in environment variables
module "aurora_auto_start" {
  count  = var.enable_aurora && (local.is_test || local.is_dev) && var.enable_python_lambda_pg ? 1 : 0
  source = "./modules/aurora-auto-start"

  function_name                  = "${var.project_name}-aurora-auto-start"
  aurora_cluster_id              = module.aurora[0].cluster_id
  aurora_cluster_arn             = module.aurora[0].cluster_arn
  aws_region                     = var.aws_region
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention

  tags = local.common_tags
}

# Python REST Lambda module (optional - disabled by default)
module "python_rest_lambda_pg" {
  count  = var.enable_python_lambda_pg ? 1 : 0
  source = "./modules/lambda"

  function_name                  = "${var.project_name}-python-rest-lambda-pg"
  s3_bucket                      = aws_s3_bucket.lambda_deployments.id
  s3_key                         = "python-rest-pg/lambda-deployment.zip"
  handler                        = "lambda_handler.handler"
  runtime                        = "python3.11"
  architectures                  = ["arm64"]  # ARM64 (Graviton2) for 20% cost savings and better performance
  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout
  log_level                      = var.log_level
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  database_url                   = local.database_url
  aurora_endpoint                = local.database_endpoint # Use RDS Proxy endpoint if available, otherwise Aurora endpoint
  database_name                  = var.database_name
  database_user                  = var.database_user
  database_password              = var.database_password

  # Aurora DSQL configuration
  enable_aurora_dsql              = var.enable_aurora_dsql
  aurora_dsql_endpoint            = var.aurora_dsql_endpoint
  aurora_dsql_port                = var.aurora_dsql_port
  iam_database_user               = var.iam_database_user
  aurora_dsql_cluster_resource_id = var.aurora_dsql_cluster_resource_id

  additional_environment_variables = var.enable_aurora && (local.is_test || local.is_dev) && var.enable_python_lambda_pg ? {
    AURORA_AUTO_START_FUNCTION_NAME = module.aurora_auto_start[0].function_name
  } : {}

  vpc_config = var.enable_aurora ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = module.vpc[0].private_subnet_ids
    } : (local.has_vpc_config ? {
      security_group_ids = [aws_security_group.lambda[0].id]
      subnet_ids         = var.subnet_ids
  } : null)

  api_name        = "${var.project_name}-python-rest-pg-http-api"
  api_description = "HTTP API for Producer API Python REST Lambda"
  cors_config = {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

# Aurora Auto-Stop Lambda (enabled for test and dev environments)
# Monitors API Gateway invocations and stops Aurora if no activity for 3 hours
module "aurora_auto_stop" {
  count  = var.enable_aurora && (local.is_test || local.is_dev) && var.enable_python_lambda_pg ? 1 : 0
  source = "./modules/aurora-auto-stop"

  function_name                  = "${var.project_name}-aurora-auto-stop"
  aurora_cluster_id              = module.aurora[0].cluster_id
  aurora_cluster_arn             = module.aurora[0].cluster_arn
  api_gateway_id                 = module.python_rest_lambda_pg[0].api_id
  aws_region                     = var.aws_region
  inactivity_hours               = 1
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  admin_email                    = var.aurora_auto_stop_admin_email

  tags = local.common_tags
}

# IAM policy to allow Python Lambda to invoke auto-start Lambda
resource "aws_iam_role_policy" "python_lambda_auto_start" {
  count = var.enable_aurora && (local.is_test || local.is_dev) && var.enable_python_lambda_pg ? 1 : 0
  name  = "${var.project_name}-python-lambda-auto-start-policy"
  role  = module.python_rest_lambda_pg[0].role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = module.aurora_auto_start[0].function_arn
      }
    ]
  })
}

# Lambda permission to allow Python Lambda to invoke auto-start Lambda
resource "aws_lambda_permission" "aurora_auto_start_python_lambda" {
  count         = var.enable_aurora && (local.is_test || local.is_dev) && var.enable_python_lambda_pg ? 1 : 0
  statement_id  = "AllowExecutionFromPythonLambda"
  action        = "lambda:InvokeFunction"
  function_name = module.aurora_auto_start[0].function_name
  principal     = "lambda.amazonaws.com"
  source_arn    = module.python_rest_lambda_pg[0].function_arn
}

# DSQL Auto-Resume Lambda (enabled for test and dev environments)
# Ensures DSQL cluster is available when API requests arrive
module "dsql_auto_resume" {
  count  = var.enable_aurora_dsql_cluster && (local.is_test || local.is_dev) && var.enable_python_lambda_dsql ? 1 : 0
  source = "./modules/dsql-auto-resume"

  function_name                  = "${var.project_name}-dsql-auto-resume"
  dsql_cluster_resource_id       = module.aurora_dsql[0].cluster_resource_id
  dsql_cluster_arn               = module.aurora_dsql[0].cluster_arn
  dsql_target_min_capacity       = 1  # Scale up to 1 ACU when resuming
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention

  tags = local.common_tags
}

# DSQL Auto-Pause Lambda (enabled for test and dev environments)
# Monitors API Gateway invocations and scales down DSQL if no activity for 3 hours
module "dsql_auto_pause" {
  count  = var.enable_aurora_dsql_cluster && (local.is_test || local.is_dev) && var.enable_python_lambda_dsql ? 1 : 0
  source = "./modules/dsql-auto-pause"

  function_name                  = "${var.project_name}-dsql-auto-pause"
  dsql_cluster_resource_id       = module.aurora_dsql[0].cluster_resource_id
  dsql_cluster_arn               = module.aurora_dsql[0].cluster_arn
  api_gateway_id                 = module.python_rest_lambda_dsql[0].api_id
  inactivity_hours               = 1
  dsql_min_capacity              = 0  # Scale down to 0 ACU (pause) when inactive
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  admin_email                    = var.aurora_auto_stop_admin_email  # Reuse same email config

  tags = local.common_tags
}

# IAM policy to allow DSQL Lambda to invoke auto-resume Lambda
resource "aws_iam_role_policy" "dsql_lambda_auto_resume" {
  count = var.enable_aurora_dsql_cluster && (local.is_test || local.is_dev) && var.enable_python_lambda_dsql ? 1 : 0
  name  = "${var.project_name}-dsql-lambda-auto-resume-policy"
  role  = module.python_rest_lambda_dsql[0].role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = module.dsql_auto_resume[0].function_arn
      }
    ]
  })
}

# Lambda permission to allow DSQL Lambda to invoke auto-resume Lambda
resource "aws_lambda_permission" "dsql_auto_resume_dsql_lambda" {
  count         = var.enable_aurora_dsql_cluster && (local.is_test || local.is_dev) && var.enable_python_lambda_dsql ? 1 : 0
  statement_id  = "AllowExecutionFromDsqlLambda"
  action        = "lambda:InvokeFunction"
  function_name = module.dsql_auto_resume[0].function_name
  principal     = "lambda.amazonaws.com"
  source_arn    = module.python_rest_lambda_dsql[0].function_arn
}

# Python REST Lambda DSQL module (separate from regular Python Lambda)
module "python_rest_lambda_dsql" {
  count  = var.enable_python_lambda_dsql ? 1 : 0
  source = "./modules/lambda"

  function_name                  = "${var.project_name}-python-rest-lambda-dsql"
  s3_bucket                      = aws_s3_bucket.lambda_deployments.id
  s3_key                         = "python-rest-dsql/lambda-deployment.zip"
  handler                        = "lambda_handler.handler"
  runtime                        = "python3.11"
  architectures                  = ["arm64"]  # ARM64 (Graviton2) for 20% cost savings and better performance
  memory_size                    = var.lambda_memory_size
  timeout                        = var.lambda_timeout
  log_level                      = var.log_level
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  database_url                   = "" # Not used for DSQL (IAM auth)
  aurora_endpoint                = "" # Not used for DSQL
  database_name                  = var.enable_aurora_dsql_cluster ? var.aurora_dsql_database_name : var.database_name
  database_user                  = "" # Not used for DSQL
  database_password              = "" # Not used for DSQL

  # Aurora DSQL configuration
  # Use created DSQL cluster if enabled, otherwise use manually provided endpoint
  # DSQL requires proper hostname for SNI - use dsql_host (format: <cluster-id>.<service-suffix>.<region>.on.aws)
  enable_aurora_dsql              = var.enable_aurora_dsql_cluster || var.enable_aurora_dsql
  aurora_dsql_endpoint            = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].vpc_endpoint_dns, "") : var.aurora_dsql_endpoint
  aurora_dsql_port                = var.aurora_dsql_port
  iam_database_user               = var.iam_database_user
  aurora_dsql_cluster_resource_id = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].cluster_resource_id, "") : var.aurora_dsql_cluster_resource_id
  dsql_host                       = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].dsql_host, "") : ""
  dsql_kms_key_arn                = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].kms_key_arn, "") : ""

  additional_environment_variables = var.enable_aurora_dsql_cluster && (local.is_test || local.is_dev) ? {
    DSQL_AUTO_RESUME_FUNCTION_NAME = module.dsql_auto_resume[0].function_name
  } : {}

  # DSQL uses VPC endpoints - Lambda must be in VPC to access the endpoint
  vpc_config = var.enable_aurora_dsql_cluster ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = module.vpc[0].private_subnet_ids
  } : null

  api_name        = "${var.project_name}-python-rest-dsql-http-api"
  api_description = "HTTP API for Producer API Python REST Lambda with Aurora DSQL"
  cors_config = {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

# DSQL Load Test Lambda module (optional - for load testing only)
module "dsql_load_test_lambda" {
  count  = var.enable_dsql_load_test_lambda ? 1 : 0
  source = "./modules/dsql-load-test-lambda"

  function_name                  = "${var.project_name}-dsql-load-test-lambda"
  s3_bucket                      = aws_s3_bucket.lambda_deployments.id
  s3_key                         = "dsql-load-test/lambda-deployment.zip"
  runtime                        = "python3.11"
  architectures                  = ["arm64"]
  memory_size                    = var.dsql_load_test_lambda_memory_size
  timeout                        = var.dsql_load_test_lambda_timeout
  log_level                      = var.log_level
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  reserved_concurrent_executions = var.dsql_load_test_lambda_reserved_concurrency

  # Aurora DSQL configuration
  # Use created DSQL cluster if enabled, otherwise use manually provided endpoint
  database_name                  = var.enable_aurora_dsql_cluster ? var.aurora_dsql_database_name : var.database_name
  aurora_dsql_endpoint           = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].vpc_endpoint_dns, "") : var.aurora_dsql_endpoint
  aurora_dsql_port               = var.aurora_dsql_port
  iam_database_user              = var.iam_database_user
  aurora_dsql_cluster_resource_id = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].cluster_resource_id, "") : var.aurora_dsql_cluster_resource_id
  dsql_host                      = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].dsql_host, "") : ""
  dsql_kms_key_arn               = var.enable_aurora_dsql_cluster ? try(module.aurora_dsql[0].kms_key_arn, "") : ""
  aws_region                     = var.aws_region

  # DSQL uses VPC endpoints - Lambda must be in VPC to access the endpoint
  # Also support manual VPC configuration if DSQL cluster is not created via Terraform
  vpc_config = var.enable_aurora_dsql_cluster && length(aws_security_group.lambda) > 0 ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = module.vpc[0].private_subnet_ids
  } : (var.vpc_id != "" && length(var.subnet_ids) > 0 && length(aws_security_group.lambda) > 0) ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = var.subnet_ids
  } : null

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

# SSM VPC Endpoints (for SSM Session Manager from private subnets)
# Required for test runner EC2 instance in private subnet to connect via SSM Session Manager
# Bastion host is in public subnet and can use internet gateway for SSM
module "ssm_endpoints" {
  count  = var.enable_dsql_test_runner_ec2 && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/ssm-endpoints"

  project_name    = var.project_name
  vpc_id          = module.vpc[0].vpc_id
  subnet_ids      = module.vpc[0].private_subnet_ids
  vpc_cidr_block  = module.vpc[0].vpc_cidr

  tags = local.common_tags
}

# S3 VPC Endpoint (Gateway type - free, no data transfer charges)
# Enables S3 access from VPC without internet gateway
# Note: S3 endpoint works with all route tables in the VPC
module "s3_endpoint" {
  count  = var.enable_bastion_host && (var.enable_aurora || var.enable_aurora_dsql_cluster) ? 1 : 0
  source = "./modules/s3-endpoint"

  project_name    = var.project_name
  vpc_id          = module.vpc[0].vpc_id
  # S3 gateway endpoint applies to all route tables in VPC automatically
  route_table_ids = module.vpc[0].private_route_table_ids

  tags = local.common_tags
}

# CloudWatch Logs VPC Endpoint (Interface type)
# Enables Lambda functions and other services in private subnets to send logs without NAT Gateway
# Reduces NAT Gateway data processing costs
module "cloudwatch_logs_endpoint" {
  count  = (var.enable_aurora || var.enable_aurora_dsql_cluster) && (var.enable_python_lambda_pg || var.enable_python_lambda_dsql) ? 1 : 0
  source = "./modules/cloudwatch-logs-endpoint"

  project_name    = var.project_name
  vpc_id          = module.vpc[0].vpc_id
  subnet_ids      = module.vpc[0].private_subnet_ids
  vpc_cidr_block  = module.vpc[0].vpc_cidr

  tags = local.common_tags
}

# ECR VPC Endpoints (Interface type)
# Enables pulling Docker images from ECR without NAT Gateway
# Useful if EC2 instances or Lambda functions need to pull container images
module "ecr_endpoint" {
  count  = (var.enable_aurora || var.enable_aurora_dsql_cluster) && (var.enable_bastion_host || var.enable_dsql_test_runner_ec2) ? 1 : 0
  source = "./modules/ecr-endpoint"

  project_name    = var.project_name
  vpc_id          = module.vpc[0].vpc_id
  subnet_ids      = module.vpc[0].private_subnet_ids
  vpc_cidr_block  = module.vpc[0].vpc_cidr

  tags = local.common_tags
}

# Secrets Manager VPC Endpoint (Interface type)
# Enables accessing secrets from private subnets without NAT Gateway
# Useful if Lambda functions or EC2 instances need to access secrets
module "secrets_manager_endpoint" {
  count  = (var.enable_aurora || var.enable_aurora_dsql_cluster) && (var.enable_python_lambda_pg || var.enable_python_lambda_dsql || var.enable_bastion_host) ? 1 : 0
  source = "./modules/secrets-manager-endpoint"

  project_name    = var.project_name
  vpc_id          = module.vpc[0].vpc_id
  subnet_ids      = module.vpc[0].private_subnet_ids
  vpc_cidr_block  = module.vpc[0].vpc_cidr

  tags = local.common_tags
}

# DSQL Test Runner EC2 Instance - Separate EC2 instance for load testing
# Access via SSM Session Manager only (no SSH, in private subnet)
module "dsql_test_runner" {
  count  = var.enable_dsql_test_runner_ec2 && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/ec2-test-runner"

  project_name                    = var.project_name
  vpc_id                          = module.vpc[0].vpc_id
  private_subnet_id               = module.vpc[0].private_subnet_ids[0]
  vpc_cidr_block                  = module.vpc[0].vpc_cidr
  instance_type                   = var.dsql_test_runner_instance_type
  iam_database_user               = var.iam_database_user
  aurora_dsql_cluster_resource_id = module.aurora_dsql[0].cluster_resource_id
  dsql_kms_key_arn                = module.aurora_dsql[0].kms_key_arn
  aws_region                      = var.aws_region
  s3_bucket_name                  = aws_s3_bucket.lambda_deployments.id
  enable_ipv6                     = var.enable_ipv6

  tags = local.common_tags
}

# EC2 Auto-Stop Lambda - Re-enabled to monitor bastion host for cost optimization

# Bastion Host
# Creates an EC2 instance in public subnet for database access via SSH
# Also used as test runner for DSQL connector (replaces dedicated test runner)
module "bastion_host" {
  count  = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/bastion-host"

  project_name                    = var.project_name
  vpc_id                          = module.vpc[0].vpc_id
  public_subnet_id                = module.vpc[0].public_subnet_ids[0]
  vpc_cidr_block                  = module.vpc[0].vpc_cidr
  instance_type                   = var.bastion_instance_type
  aurora_dsql_cluster_resource_id = module.aurora_dsql[0].cluster_resource_id
  dsql_kms_key_arn                = module.aurora_dsql[0].kms_key_arn
  aws_region                      = var.aws_region
  s3_bucket_name                  = aws_s3_bucket.lambda_deployments.id
  msk_cluster_name                = var.enable_msk && var.enable_vpc ? module.msk_serverless[0].cluster_name : ""
  ssh_public_key                  = var.bastion_ssh_public_key
  ssh_allowed_cidr_blocks         = var.bastion_ssh_allowed_cidr_blocks
  allocate_elastic_ip            = var.bastion_allocate_elastic_ip
  enable_ipv6                     = var.enable_ipv6

  tags = local.common_tags
}

# EC2 Auto-Stop Lambda for Bastion Host
# Monitors SSM sessions, DSQL API calls, and EC2 activity, stops bastion if no activity for 30 minutes
# Sends email notification to rick when instance is stopped
module "ec2_auto_stop" {
  count  = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/ec2-auto-stop"

  function_name                  = "${var.project_name}-bastion-auto-stop"
  ec2_instance_id                = module.bastion_host[0].instance_id
  bastion_role_arn               = module.bastion_host[0].iam_role_arn
  inactivity_hours               = 0.5  # 30 minutes
  aws_region                     = var.aws_region
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  admin_email                    = var.aurora_auto_stop_admin_email  # Set to rick's email in terraform.tfvars

  tags = local.common_tags
}

# EC2 Auto-Stop Lambda for Test Runner Instance
# Monitors SSM sessions, DSQL API calls, and EC2 activity, stops test runner if no activity for 30 minutes
# Sends email notification when instance is stopped
module "ec2_auto_stop_test_runner" {
  count  = var.enable_dsql_test_runner_ec2 && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/ec2-auto-stop"

  function_name                  = "${var.project_name}-test-runner-auto-stop"
  ec2_instance_id                = module.dsql_test_runner[0].instance_id
  bastion_role_arn               = module.dsql_test_runner[0].iam_role_arn
  inactivity_hours               = 0.5  # 30 minutes
  aws_region                     = var.aws_region
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention
  admin_email                    = var.aurora_auto_stop_admin_email  # Set to rick's email in terraform.tfvars

  tags = local.common_tags
}

# Grant Bastion Host IAM Role Access to DSQL IAM User
# 
# DSQL requires IAM authentication even for admin operations, creating a chicken-and-egg problem.
# We use a Lambda function to grant IAM role access. The Lambda's IAM role must first be mapped
# to the postgres user in DSQL (one-time manual step), then Terraform can manage subsequent grants.
#
# One-time setup (run once manually from a machine with DSQL admin access):
#   AWS IAM GRANT postgres TO 'arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-dsql-iam-grant-role';
#
# After that, Terraform will automatically grant the bastion role access via Lambda.

# Lambda function to grant IAM role access (shared by bastion and test runner)
# The Lambda can grant multiple IAM roles - role_arn here is just for module initialization
module "dsql_iam_grant" {
  count  = (var.enable_bastion_host || var.enable_dsql_test_runner_ec2) && var.enable_aurora_dsql_cluster ? 1 : 0
  source = "./modules/dsql-iam-grant"

  project_name            = var.project_name
  dsql_host              = module.aurora_dsql[0].dsql_host
  dsql_cluster_resource_id = module.aurora_dsql[0].cluster_resource_id
  iam_user               = var.iam_database_user
  role_arn               = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role"
  aws_region             = var.aws_region
  tags                   = local.common_tags
}

# Grant IAM role access to DSQL via Lambda function (for bastion)
resource "aws_lambda_invocation" "grant_bastion_iam_access" {
  count = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? 1 : 0

  function_name = module.dsql_iam_grant[0].lambda_function_name

  input = jsonencode({
    dsql_host = module.aurora_dsql[0].dsql_host
    iam_user  = var.iam_database_user
    role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role"
    region    = var.aws_region
  })

  depends_on = [
    module.dsql_iam_grant,
    module.aurora_dsql,
  ]
}

# Grant test runner IAM role access to DSQL via Lambda function
# Reuse the same Lambda function (it can grant multiple roles)
resource "aws_lambda_invocation" "grant_test_runner_iam_access" {
  count = var.enable_dsql_test_runner_ec2 && var.enable_aurora_dsql_cluster ? 1 : 0

  function_name = module.dsql_iam_grant[0].lambda_function_name

  input = jsonencode({
    dsql_host = module.aurora_dsql[0].dsql_host
    iam_user  = var.iam_database_user
    role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-dsql-test-runner-role"
    region    = var.aws_region
  })

  depends_on = [
    module.dsql_iam_grant,
    module.aurora_dsql,
  ]
}

# ============================================================================
# MSK Serverless Cluster Module
# ============================================================================
module "msk_serverless" {
  count  = var.enable_msk && var.enable_vpc ? 1 : 0
  source = "./modules/msk-serverless"

  cluster_name = var.msk_cluster_name != "" ? var.msk_cluster_name : "${var.project_name}-msk-cluster"
  vpc_id       = module.vpc[0].vpc_id
  subnet_ids   = module.vpc[0].private_subnet_ids
  vpc_cidr     = module.vpc[0].vpc_cidr

  tags = local.common_tags
}

# ============================================================================
# MSK Connect Module (Debezium CDC Connector)
# ============================================================================
module "msk_connect" {
  count  = var.enable_msk && var.enable_vpc && var.enable_aurora ? 1 : 0
  source = "./modules/msk-connect"

  project_name         = var.project_name
  msk_cluster_name     = module.msk_serverless[0].cluster_name
  msk_bootstrap_servers = module.msk_serverless[0].bootstrap_brokers_sasl_iam
  vpc_id               = module.vpc[0].vpc_id
  subnet_ids           = module.vpc[0].private_subnet_ids
  vpc_cidr             = module.vpc[0].vpc_cidr

  connector_configuration = {
    "connector.class"                    = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"                          = "1"
    "database.hostname"                  = module.aurora[0].cluster_endpoint
    "database.port"                      = "5432"
    "database.user"                      = var.database_user
    "database.password"                  = var.database_password
    "database.dbname"                    = var.database_name
    "database.server.name"               = "aurora-postgres-cdc"
    "topic.prefix"                       = "aurora-postgres-cdc"
    "database.sslmode"                  = "require"
    "table.include.list"                 = "public.event_headers"
    "plugin.name"                        = "pgoutput"
    "slot.name"                          = "event_headers_msk_debezium_slot"
    "publication.name"                   = "event_headers_msk_publication"
    "publication.autocreate.mode"        = "filtered"
    "snapshot.mode"                      = "initial"
    "key.converter"                      = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"       = "false"
    "value.converter"                    = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable"     = "false"
    "transforms"                         = "unwrap,route"
    "transforms.unwrap.type"             = "io.debezium.transforms.ExtractNewRecordState"
    "transforms.unwrap.drop.tombstones"  = "false"
    "transforms.unwrap.add.fields"       = "op,table,ts_ms"
    "transforms.unwrap.add.fields.prefix" = "__"
    "transforms.unwrap.delete.handling.mode" = "rewrite"
    "transforms.route.type"              = "org.apache.kafka.connect.transforms.RegexRouter"
    "transforms.route.regex"             = "aurora-postgres-cdc\\.public\\.event_headers"
    "transforms.route.replacement"       = "raw-event-headers"
    "errors.tolerance"                   = "all"
    "errors.log.enable"                  = "true"
    "errors.log.include.messages"        = "true"
  }

  connector_mcu_count  = 1
  connector_min_workers = 1
  connector_max_workers = 2
  log_retention_days   = local.cloudwatch_logs_retention

  tags = local.common_tags
}

# Security group rule: Allow MSK Connect to access Aurora
resource "aws_security_group_rule" "aurora_from_msk_connect" {
  count = var.enable_msk && var.enable_vpc && var.enable_aurora ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.msk_connect[0].security_group_id
  security_group_id        = module.aurora[0].security_group_id
  description              = "Allow MSK Connect to access Aurora PostgreSQL"
}

# Security group rule: Allow Flink to access MSK
resource "aws_security_group_rule" "msk_from_flink" {
  count = var.enable_msk && var.enable_vpc ? 1 : 0

  type                     = "ingress"
  from_port                = 9098
  to_port                  = 9098
  protocol                 = "tcp"
  source_security_group_id = module.managed_flink[0].security_group_id
  security_group_id        = module.msk_serverless[0].security_group_id
  description              = "Allow Flink application to access MSK (IAM auth port)"
}

# ============================================================================
# Managed Service for Apache Flink Module
# ============================================================================
module "managed_flink" {
  count  = var.enable_msk && var.enable_vpc ? 1 : 0
  source = "./modules/managed-flink"

  project_name         = var.project_name
  msk_cluster_name     = module.msk_serverless[0].cluster_name
  msk_bootstrap_servers = module.msk_serverless[0].bootstrap_brokers_sasl_iam
  flink_app_jar_key    = var.flink_app_jar_key
  parallelism          = 1
  parallelism_per_kpu  = 1
  enable_glue_schema_registry = var.enable_glue_schema_registry
  log_retention_days   = local.cloudwatch_logs_retention

  # VPC Configuration for Flink to access MSK
  vpc_id              = module.vpc[0].vpc_id
  subnet_ids          = module.vpc[0].private_subnet_ids
  security_group_ids  = [] # Flink will create its own security group if needed

  tags = local.common_tags
}

# ============================================================================
# Glue Schema Registry Module
# ============================================================================
module "glue_schema_registry" {
  count  = var.enable_msk && var.enable_glue_schema_registry ? 1 : 0
  source = "./modules/glue-schema-registry"

  registry_name = "${var.project_name}-schema-registry"
  description   = "Schema registry for CDC streaming events"

  tags = local.common_tags
}
