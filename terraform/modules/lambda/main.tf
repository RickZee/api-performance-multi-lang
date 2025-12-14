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

# IAM policy for Aurora DSQL database authentication (if DSQL is enabled)
# Note: If cluster_resource_id is empty, we'll use a wildcard pattern that will be updated after cluster creation
resource "aws_iam_role_policy" "lambda_dsql_auth" {
  count = var.enable_aurora_dsql && var.iam_database_user != "" ? 1 : 0
  name  = "${var.function_name}-dsql-auth-policy"
  role  = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect"
        ]
        # DSQL uses different resource format than RDS
        # Format: arn:aws:dsql:region:account:cluster/cluster-id
        # Note: DSQL doesn't include username in resource ARN like RDS does
        Resource = var.aurora_dsql_cluster_resource_id != "" ? "arn:aws:dsql:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.aurora_dsql_cluster_resource_id}" : "arn:aws:dsql:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/*"
      }
    ]
  })

  lifecycle {
    # Allow policy to be updated when cluster_resource_id becomes available
    create_before_destroy = true
  }
}

# IAM policy for KMS decrypt access (required for DSQL connections)
# DSQL uses KMS encryption, and Lambda needs decrypt permission to connect
resource "aws_iam_role_policy" "lambda_dsql_kms" {
  count = var.enable_aurora_dsql && var.dsql_kms_key_arn != "" ? 1 : 0
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

# Data sources for IAM policy
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda function
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_execution.arn
  handler       = var.handler
  runtime       = var.runtime
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout

  s3_bucket = var.s3_bucket
  s3_key    = var.s3_key

  environment {
    variables = merge(
      {
        LOG_LEVEL                       = var.log_level
        DATABASE_URL                    = var.database_url
        AURORA_ENDPOINT                 = var.aurora_endpoint
        DATABASE_NAME                   = var.database_name
        DATABASE_USER                   = var.database_user
        DATABASE_PASSWORD               = var.database_password
        AURORA_DSQL_ENDPOINT            = var.enable_aurora_dsql ? var.aurora_dsql_endpoint : ""
        AURORA_DSQL_PORT                = var.enable_aurora_dsql ? tostring(var.aurora_dsql_port) : ""
        IAM_USERNAME                    = var.enable_aurora_dsql ? var.iam_database_user : ""
        AURORA_DSQL_CLUSTER_RESOURCE_ID = var.enable_aurora_dsql ? var.aurora_dsql_cluster_resource_id : ""
        DSQL_HOST                       = var.enable_aurora_dsql ? var.dsql_host : ""
      },
      var.additional_environment_variables
    )
  }

  vpc_config {
    security_group_ids = var.vpc_config != null ? var.vpc_config.security_group_ids : []
    subnet_ids         = var.vpc_config != null ? var.vpc_config.subnet_ids : []
  }

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_cloudwatch_log_group.lambda
  ]

  tags = var.tags
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "this" {
  name          = var.api_name
  description   = var.api_description
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_config.allow_origins
    allow_methods = var.cors_config.allow_methods
    allow_headers = var.cors_config.allow_headers
    max_age       = var.cors_config.max_age
  }

  tags = var.tags
}

# API Gateway integration
resource "aws_apigatewayv2_integration" "lambda" {
  api_id = aws_apigatewayv2_api.this.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# API Gateway route (root path)
resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# API Gateway route (catch-all proxy)
resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = var.tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

