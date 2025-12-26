# MSK Connect Module
# Creates MSK Connect custom plugin and connector for Debezium CDC

# S3 Bucket for MSK Connect plugin artifacts
resource "aws_s3_bucket" "msk_connect_plugins" {
  bucket = "${var.project_name}-msk-connect-plugins-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-msk-connect-plugins"
    }
  )
}

resource "aws_s3_bucket_versioning" "msk_connect_plugins" {
  bucket = aws_s3_bucket.msk_connect_plugins.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_connect_plugins" {
  bucket = aws_s3_bucket.msk_connect_plugins.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role for MSK Connect
resource "aws_iam_role" "msk_connect" {
  name = "${var.project_name}-msk-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for MSK Connect to access MSK
resource "aws_iam_role_policy" "msk_connect_msk" {
  name = "${var.project_name}-msk-connect-msk-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.msk_cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.msk_cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/${var.msk_cluster_name}/*"
      }
    ]
  })
}

# IAM Policy for MSK Connect to access S3 (for plugin storage)
resource "aws_iam_role_policy" "msk_connect_s3" {
  name = "${var.project_name}-msk-connect-s3-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.msk_connect_plugins.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.msk_connect_plugins.arn
      }
    ]
  })
}

# IAM Policy for MSK Connect to access CloudWatch Logs
resource "aws_iam_role_policy" "msk_connect_logs" {
  name = "${var.project_name}-msk-connect-logs-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# MSK Connect Custom Plugin (Debezium PostgreSQL)
resource "aws_mskconnect_custom_plugin" "debezium_postgres" {
  name         = "${var.project_name}-debezium-postgres-plugin"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.msk_connect_plugins.arn
      file_key   = "debezium-connector-postgres.zip"
    }
  }

  description = "Debezium PostgreSQL connector plugin for MSK Connect"

  tags = var.tags
}

# MSK Connect Connector
resource "aws_mskconnect_connector" "postgres_cdc" {
  name = "${var.project_name}-postgres-cdc-connector"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count      = var.connector_mcu_count
      min_worker_count = var.connector_min_workers
      max_worker_count = var.connector_max_workers
      scale_in_policy {
        cpu_utilization_percentage = 20
      }
      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = var.connector_configuration

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.msk_bootstrap_servers

      vpc {
        security_groups = [aws_security_group.msk_connect.id]
        subnets        = var.subnet_ids
      }
    }
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.debezium_postgres.arn
      revision = aws_mskconnect_custom_plugin.debezium_postgres.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
    }
  }

  tags = var.tags
}

# Security Group for MSK Connect
resource "aws_security_group" "msk_connect" {
  name        = "${var.project_name}-msk-connect-sg"
  description = "Security group for MSK Connect workers"
  vpc_id      = var.vpc_id

  # Allow outbound to MSK
  egress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "MSK IAM auth port"
  }

  # Allow outbound to PostgreSQL (Aurora)
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL access"
  }

  # Allow all outbound for plugin downloads, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-msk-connect-sg"
    }
  )
}

# CloudWatch Log Group for MSK Connect
resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/mskconnect/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

