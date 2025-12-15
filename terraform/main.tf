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
  # - test: Standard testing setup (3 days logs, 3 days backups, RDS Proxy enabled, db.r5.large)
  is_dev  = var.environment == "dev"
  is_test = var.environment == "test"

  # CloudWatch Logs retention: 1 day for dev, 3 days for test
  cloudwatch_logs_retention = var.cloudwatch_logs_retention_days != null ? var.cloudwatch_logs_retention_days : (
    local.is_dev ? 1 : 3
  )

  # Backup retention: 1 day for dev, 3 days for test
  backup_retention = var.backup_retention_period != null ? var.backup_retention_period : (
    local.is_dev ? 1 : 3
  )

  # Aurora instance class: db.t3.medium for dev (db.t3.small not supported for 15.14), db.r5.large for test
  # Note: Can be overridden in terraform.tfvars (e.g., db.t4g.medium for ARM-based cost savings)
  aurora_instance_class = var.aurora_instance_class != null ? var.aurora_instance_class : (
    local.is_dev ? "db.t3.medium" : "db.r5.large"
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
  inactivity_hours               = 3
  cloudwatch_logs_retention_days = local.cloudwatch_logs_retention

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

  additional_environment_variables = {}

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
# Bastion host is in public subnet and can use internet gateway for SSM
# These endpoints remain configured for private subnets only (no change needed)
# Note: Existing endpoints are fine - bastion doesn't need them

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

# DSQL Test Runner EC2 Instance - REMOVED
# Now using bastion host as test runner instead
# Access via SSM Session Manager or SSH

# EC2 Auto-Stop Lambda - REMOVED (no longer needed with bastion host)

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
  ssh_public_key                  = var.bastion_ssh_public_key
  ssh_allowed_cidr_blocks         = var.bastion_ssh_allowed_cidr_blocks
  allocate_elastic_ip            = var.bastion_allocate_elastic_ip

  tags = local.common_tags
}

# Grant Bastion Host IAM Role Access to DSQL IAM User
# 
# DSQL requires IAM authentication even for admin operations, creating a chicken-and-egg problem.
# The simplest solution is to grant the bastion role directly using a one-time manual step,
# then Terraform can manage it going forward.
#
# One-time setup (run once manually from a machine with DSQL admin access):
#   AWS IAM GRANT ${var.iam_database_user} TO 'arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role';
#
# This null_resource outputs the command to run and can be triggered on demand.
resource "null_resource" "grant_bastion_iam_access" {
  count = var.enable_bastion_host && var.enable_aurora_dsql_cluster ? 1 : 0

  triggers = {
    bastion_instance_id = module.bastion_host[0].instance_id
    dsql_cluster_id     = module.aurora_dsql[0].cluster_resource_id
    iam_user            = var.iam_database_user
    bastion_role_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role"
  }

  # Output the command that needs to be run
  # This can be run manually or via a separate automation
  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "DSQL IAM Role Mapping Required"
      echo "=========================================="
      echo ""
      echo "Run this command from a machine with DSQL admin access:"
      echo ""
      echo "  AWS IAM GRANT ${var.iam_database_user} TO 'arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role';"
      echo ""
      echo "This is a one-time setup. After this, the connector will be able to connect."
      echo ""
      echo "To connect to DSQL, you need:"
      echo "  1. A machine with IAM role/user mapped to postgres user in DSQL"
      echo "  2. Or use AWS Console/CLI if available"
      echo ""
      echo "DSQL Host: ${module.aurora_dsql[0].dsql_host}"
      echo "IAM User: ${var.iam_database_user}"
      echo "Bastion Role: arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-bastion-role"
      echo "=========================================="
    EOT
  }

  depends_on = [
    module.bastion_host,
    module.aurora_dsql,
  ]
}

