# Amazon MSK Serverless Module
# Creates an MSK Serverless cluster with IAM authentication

# MSK Serverless Cluster
resource "aws_msk_serverless_cluster" "this" {
  cluster_name = var.cluster_name

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

# Security Group for MSK
resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK Serverless cluster"
  vpc_id      = var.vpc_id

  # Allow inbound from VPC CIDR for Kafka clients
  ingress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka IAM auth port from VPC"
  }

  # Allow inbound from VPC CIDR for plaintext (if needed)
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka plaintext port from VPC"
  }

  # Allow inbound from VPC CIDR for TLS
  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka TLS port from VPC"
  }

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
      Name = "${var.cluster_name}-sg"
    }
  )
}

# IAM Policy for MSK access (for consumers/producers)
resource "aws_iam_policy" "msk_access" {
  name        = "${var.cluster_name}-msk-access-policy"
  description = "IAM policy for MSK Serverless cluster access"

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
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/${var.cluster_name}/*"
      }
    ]
  })

  tags = var.tags
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

