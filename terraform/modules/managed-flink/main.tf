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

# IAM Policy for Flink to access VPC resources (required for VPC configuration)
resource "aws_iam_role_policy" "flink_vpc" {
  count = var.vpc_id != null ? 1 : 0
  name  = "${var.project_name}-flink-vpc-policy"
  role  = aws_iam_role.flink_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
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

    # VPC Configuration for Flink to access MSK
    dynamic "run_configuration" {
      for_each = var.vpc_id != null && length(var.subnet_ids) > 0 ? [1] : []
      content {
        application_restore_configuration {
          application_restore_type = "SKIP_RESTORE_FROM_SNAPSHOT"
        }
        
        flink_run_configuration {
          allow_non_restored_state = false
        }
      }
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_app.arn
  }

  tags = var.tags
}

# VPC Configuration for Flink Application
# Note: aws_kinesisanalyticsv2_application does not support VPC configuration directly.
# VPC must be added via the AWS API after application creation.
resource "null_resource" "flink_vpc_config" {
  count = var.vpc_id != null && length(var.subnet_ids) > 0 ? 1 : 0

  depends_on = [
    aws_kinesisanalyticsv2_application.flink_app,
    aws_security_group.flink_app
  ]

  triggers = {
    application_name   = aws_kinesisanalyticsv2_application.flink_app.name
    subnet_ids         = join(",", var.subnet_ids)
    security_group_ids = join(",", length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.flink_app[0].id])
    # Note: We don't track version_id in triggers as it changes, but we fetch it dynamically in the provisioner
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      APP_NAME="${aws_kinesisanalyticsv2_application.flink_app.name}"
      REGION="${data.aws_region.current.name}"
      SUBNET_IDS="${join(",", var.subnet_ids)}"
      SECURITY_GROUP_IDS="${join(",", length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.flink_app[0].id])}"
      
      # Check if VPC config already exists
      VPC_CONFIG=$(aws kinesisanalyticsv2 describe-application \
        --application-name "$APP_NAME" \
        --region "$REGION" \
        --query 'ApplicationDetail.VpcConfigurations' \
        --output json 2>&1 || echo "null")
      
      if [ "$VPC_CONFIG" = "null" ] || [ "$VPC_CONFIG" = "[]" ]; then
        echo "Adding VPC configuration to Flink application..."
        
        # Get current application version
        CURRENT_VERSION=$(aws kinesisanalyticsv2 describe-application \
          --application-name "$APP_NAME" \
          --region "$REGION" \
          --query 'ApplicationDetail.ApplicationVersionId' \
          --output text)
        
        # Wait for application to be in READY state (required for VPC config)
        echo "Waiting for application to be in READY state..."
        MAX_WAIT=300
        ELAPSED=0
        while [ $ELAPSED -lt $MAX_WAIT ]; do
          STATUS=$(aws kinesisanalyticsv2 describe-application \
            --application-name "$APP_NAME" \
            --region "$REGION" \
            --query 'ApplicationDetail.ApplicationStatus' \
            --output text 2>&1 || echo "UNKNOWN")
          
          if [ "$STATUS" = "READY" ]; then
            echo "Application is READY, proceeding with VPC configuration..."
            break
          elif [ "$STATUS" = "RUNNING" ] || [ "$STATUS" = "STARTING" ]; then
            echo "Application is $STATUS, waiting for READY state... ($${ELAPSED}s elapsed)"
            sleep 10
            ELAPSED=$((ELAPSED + 10))
          else
            echo "Application status: $STATUS"
            sleep 5
            ELAPSED=$((ELAPSED + 5))
          fi
        done
        
        if [ "$STATUS" != "READY" ]; then
          echo "WARNING: Application is not in READY state (current: $STATUS). Attempting VPC configuration anyway..."
        fi
        
        # Add VPC configuration
        aws kinesisanalyticsv2 add-application-vpc-configuration \
          --application-name "$APP_NAME" \
          --current-application-version-id "$CURRENT_VERSION" \
          --vpc-configuration "SubnetIds=$SUBNET_IDS,SecurityGroupIds=$SECURITY_GROUP_IDS" \
          --region "$REGION" \
          --output json
        
        echo "VPC configuration added successfully"
        
        # Wait a moment for configuration to propagate
        sleep 10
        
        # Verify VPC config was added
        VPC_CONFIG_AFTER=$(aws kinesisanalyticsv2 describe-application \
          --application-name "$APP_NAME" \
          --region "$REGION" \
          --query 'ApplicationDetail.VpcConfigurations' \
          --output json)
        
        if [ "$VPC_CONFIG_AFTER" != "null" ] && [ "$VPC_CONFIG_AFTER" != "[]" ]; then
          echo "VPC configuration verified successfully"
        else
          echo "WARNING: VPC configuration may not have been applied correctly"
        fi
      else
        echo "VPC configuration already exists, skipping..."
      fi
    EOT
  }
}

# Security Group for Flink Application
resource "aws_security_group" "flink_app" {
  count = var.vpc_id != null ? 1 : 0

  name        = "${var.project_name}-flink-app-sg"
  description = "Security group for Flink application to access MSK"
  vpc_id      = var.vpc_id

  # Allow outbound to MSK (IAM auth port)
  egress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MSK IAM auth port"
  }

  # Allow all outbound for other services
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
      Name = "${var.project_name}-flink-app-sg"
    }
  )
}

# CloudWatch Log Stream for Flink Application
resource "aws_cloudwatch_log_stream" "flink_app" {
  name           = "${var.project_name}-flink-app-stream"
  log_group_name = aws_cloudwatch_log_group.flink_app.name
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

