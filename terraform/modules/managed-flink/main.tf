# Managed Service for Apache Flink Module
# Creates a Flink application that processes events from MSK

# S3 Bucket for Flink application artifacts
resource "aws_s3_bucket" "flink_apps" {
  bucket = "${var.project_name}-flink-apps-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-flink-apps"
    }
  )
}

resource "aws_s3_bucket_versioning" "flink_apps" {
  bucket = aws_s3_bucket.flink_apps.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flink_apps" {
  bucket = aws_s3_bucket.flink_apps.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role for Flink Application
resource "aws_iam_role" "flink_app" {
  name = "${var.project_name}-flink-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Flink to access MSK
resource "aws_iam_role_policy" "flink_msk" {
  name = "${var.project_name}-flink-msk-policy"
  role = aws_iam_role.flink_app.id

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

# IAM Policy for Flink to access S3 (for checkpointing and artifacts)
resource "aws_iam_role_policy" "flink_s3" {
  name = "${var.project_name}-flink-s3-policy"
  role = aws_iam_role.flink_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.flink_apps.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.flink_apps.arn
      }
    ]
  })
}

# IAM Policy for Flink to access CloudWatch Logs
resource "aws_iam_role_policy" "flink_logs" {
  name = "${var.project_name}-flink-logs-policy"
  role = aws_iam_role.flink_app.id

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

# IAM Policy for Flink to access Glue Schema Registry (if used)
resource "aws_iam_role_policy" "flink_glue" {
  count = var.enable_glue_schema_registry ? 1 : 0
  name  = "${var.project_name}-flink-glue-policy"
  role  = aws_iam_role.flink_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetSchema",
          "glue:GetSchemaVersion",
          "glue:GetSchemaVersionsDiff",
          "glue:RegisterSchemaVersion",
          "glue:PutSchemaVersionMetadata",
          "glue:QuerySchemaVersionMetadata",
          "glue:RemoveSchemaVersionMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Flink Application
resource "aws_cloudwatch_log_group" "flink_app" {
  name              = "/aws/kinesisanalytics/${var.project_name}-flink-app"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# Managed Service for Apache Flink Application
resource "aws_kinesisanalyticsv2_application" "flink_app" {
  name        = "${var.project_name}-flink-app"
  description = "Flink application for event filtering and routing"
  runtime_environment = "FLINK-1_18"

  service_execution_role = aws_iam_role.flink_app.arn

  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = aws_s3_bucket.flink_apps.arn
          file_key   = var.flink_app_jar_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    environment_properties {
      property_group {
        property_group_id = "kafka.source"
        property_map = {
          "bootstrap.servers" = var.msk_bootstrap_servers
          "security.protocol"  = "SASL_SSL"
          "sasl.mechanism"     = "AWS_MSK_IAM"
        }
      }
      property_group {
        property_group_id = "kafka.sink"
        property_map = {
          "bootstrap.servers" = var.msk_bootstrap_servers
          "security.protocol" = "SASL_SSL"
          "sasl.mechanism"    = "AWS_MSK_IAM"
        }
      }
    }

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "DEFAULT"
        checkpointing_enabled = true
        checkpoint_interval    = 60000 # 1 minute
        min_pause_between_checkpoints = 5000
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        auto_scaling_enabled = true
        parallelism          = var.parallelism
        parallelism_per_kpu  = var.parallelism_per_kpu
      }
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_app.arn
  }

  tags = var.tags
}

# CloudWatch Log Stream for Flink Application
resource "aws_cloudwatch_log_stream" "flink_app" {
  name           = "${var.project_name}-flink-app-stream"
  log_group_name = aws_cloudwatch_log_group.flink_app.name
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

