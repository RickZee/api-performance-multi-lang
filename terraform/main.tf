provider "aws" {
  region = var.aws_region
}

# S3 bucket for Lambda deployments
resource "aws_s3_bucket" "lambda_deployments" {
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-lambda-deployments-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
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

    noncurrent_version_expiration {
      noncurrent_days = 30
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

# Security group for Lambda functions (if VPC enabled)
resource "aws_security_group" "lambda" {
  count = var.enable_vpc ? 1 : 0

  name        = "${var.project_name}-lambda-sg"
  description = "Security group for Lambda functions to access Aurora Serverless"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound to Aurora Serverless"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-lambda-sg"
    }
  )
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Local values for database connection string
locals {
  has_database_url = var.database_url != ""
  has_vpc_config   = var.enable_vpc && var.vpc_id != "" && length(var.subnet_ids) > 0

  database_url = local.has_database_url ? var.database_url : (
    var.aurora_endpoint != "" ? "postgresql://${var.database_user}:${var.database_password}@${var.aurora_endpoint}:5432/${var.database_name}" : ""
  )

  common_tags = merge(
    var.tags,
    {
      Project = var.project_name
    }
  )
}

# gRPC Lambda module
module "grpc_lambda" {
  source = "./modules/lambda"

  function_name   = "${var.project_name}-go-grpc-lambda"
  s3_bucket       = aws_s3_bucket.lambda_deployments.id
  s3_key          = "grpc/lambda-deployment.zip"
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  architectures   = ["x86_64"]
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout
  log_level       = var.log_level
  database_url    = local.database_url
  aurora_endpoint = var.aurora_endpoint
  database_name   = var.database_name
  database_user   = var.database_user
  database_password = var.database_password

  vpc_config = local.has_vpc_config ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = var.subnet_ids
  } : null

  api_name        = "${var.project_name}-go-grpc-http-api"
  api_description = "HTTP API for Producer API Go gRPC Lambda with gRPC-Web support"
  cors_config = {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "x-grpc-web", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

# REST Lambda module
module "rest_lambda" {
  source = "./modules/lambda"

  function_name   = "${var.project_name}-go-rest-lambda"
  s3_bucket       = aws_s3_bucket.lambda_deployments.id
  s3_key          = "rest/lambda-deployment.zip"
  handler         = "bootstrap"
  runtime         = "provided.al2023"
  architectures   = ["x86_64"]
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout
  log_level       = var.log_level
  database_url    = local.database_url
  aurora_endpoint = var.aurora_endpoint
  database_name   = var.database_name
  database_user   = var.database_user
  database_password = var.database_password

  vpc_config = local.has_vpc_config ? {
    security_group_ids = [aws_security_group.lambda[0].id]
    subnet_ids         = var.subnet_ids
  } : null

  api_name        = "${var.project_name}-go-rest-http-api"
  api_description = "HTTP API for Producer API Go REST Lambda"
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

  project_name     = var.project_name
  database_name    = var.database_name
  database_user    = var.database_user
  database_password = var.database_password
  vpc_id           = var.vpc_id
  subnet_ids       = var.subnet_ids

  tags = local.common_tags
}

