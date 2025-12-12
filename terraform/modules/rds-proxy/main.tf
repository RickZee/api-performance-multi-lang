# RDS Proxy Module
# Provides connection pooling for Lambda functions to Aurora PostgreSQL

# Secrets Manager Secret for RDS Proxy authentication
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-rds-proxy-db-credentials"
  description = "Database credentials for RDS Proxy"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-rds-proxy-db-credentials"
    }
  )
}

# Secrets Manager Secret Version
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.database_user
    password = var.database_password
  })
}

# IAM Role for RDS Proxy
resource "aws_iam_role" "rds_proxy" {
  name = "${var.project_name}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for RDS Proxy to access Secrets Manager
resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "${var.project_name}-rds-proxy-secrets-policy"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# Security Group for RDS Proxy
resource "aws_security_group" "rds_proxy" {
  name        = "${var.project_name}-rds-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-rds-proxy-sg"
    }
  )
}

# Security Group Rules: Allow inbound from Lambda security groups
resource "aws_security_group_rule" "rds_proxy_ingress_from_lambda" {
  for_each = toset(var.lambda_security_group_ids)

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.rds_proxy.id
  description              = "Allow inbound from Lambda security group"
}

# Security Group Rule: Allow outbound to Aurora
resource "aws_security_group_rule" "rds_proxy_egress_to_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.aurora_security_group_id
  security_group_id        = aws_security_group.rds_proxy.id
  description              = "Allow outbound to Aurora PostgreSQL"
}

# RDS Proxy
resource "aws_db_proxy" "this" {
  name                   = "${var.project_name}-rds-proxy"
  engine_family          = "POSTGRESQL"
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  require_tls            = true
  idle_client_timeout    = 1800 # 30 minutes
  debug_logging          = var.enable_debug_logging

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  role_arn = aws_iam_role.rds_proxy.arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-rds-proxy"
    }
  )
}

# RDS Proxy Default Target Group
resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    connection_borrow_timeout     = var.connection_borrow_timeout
    session_pinning_filters      = []
  }
}

# RDS Proxy Target (Aurora Cluster)
resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = "default"
  db_cluster_identifier  = var.aurora_cluster_id
}

# CloudWatch Log Group for RDS Proxy
resource "aws_cloudwatch_log_group" "rds_proxy" {
  count             = var.enable_debug_logging ? 1 : 0
  name              = "/aws/rds-proxy/${aws_db_proxy.this.name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

