# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM policy for VPC access (if VPC is configured)
resource "aws_iam_role_policy" "lambda_vpc" {
  count = var.vpc_config != null ? 1 : 0
  name  = "${var.function_name}-vpc-policy"
  role  = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for Aurora DSQL database authentication
resource "aws_iam_role_policy" "lambda_dsql_auth" {
  name = "${var.function_name}-dsql-auth-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect"
        ]
        Resource = "arn:aws:dsql:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.aurora_dsql_cluster_resource_id}"
      }
    ]
  })
}

# IAM policy for KMS decrypt access (required for DSQL connections)
resource "aws_iam_role_policy" "lambda_dsql_kms" {
  count = var.dsql_kms_key_arn != "" ? 1 : 0
  name  = "${var.function_name}-dsql-kms-policy"
  role  = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.dsql_kms_key_arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Data source to track S3 object changes (ETag)
data "aws_s3_object" "lambda_package" {
  bucket = var.s3_bucket
  key    = var.s3_key
}

# Lambda function
resource "aws_lambda_function" "dsql_load_test" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_execution.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.runtime
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout

  s3_bucket        = var.s3_bucket
  s3_key           = var.s3_key
  source_code_hash = data.aws_s3_object.lambda_package.etag

  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      LOG_LEVEL                       = var.log_level
      DATABASE_NAME                   = var.database_name
      AURORA_DSQL_ENDPOINT            = var.aurora_dsql_endpoint
      AURORA_DSQL_PORT                = tostring(var.aurora_dsql_port)
      IAM_USERNAME                    = var.iam_database_user
      AURORA_DSQL_CLUSTER_RESOURCE_ID = var.aurora_dsql_cluster_resource_id
      DSQL_HOST                       = var.dsql_host != "" ? var.dsql_host : var.aurora_dsql_endpoint
      AWS_REGION                      = var.aws_region
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      security_group_ids = var.vpc_config.security_group_ids
      subnet_ids         = var.vpc_config.subnet_ids
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_cloudwatch_log_group.lambda
  ]

  tags = var.tags
}
