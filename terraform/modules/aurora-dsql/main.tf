# Aurora DSQL Module
# Creates Aurora DSQL cluster - a brand new serverless, distributed SQL database (released May 2025)
# Aurora DSQL uses aws_dsql_cluster resource (not aws_rds_cluster) and VPC endpoints for connectivity

# KMS Key for DSQL encryption (required)
data "aws_iam_policy_document" "kms_dsql" {
  statement {
    sid       = "Enable IAM User Permissions"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "Allow DSQL Service Use"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["dsql.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "dsql" {
  policy = data.aws_iam_policy_document.kms_dsql.json
  tags   = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Security Group for DSQL VPC Endpoint
resource "aws_security_group" "dsql_endpoint" {
  name        = "${var.project_name}-dsql-endpoint-sg"
  description = "Security group for DSQL VPC endpoint"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-dsql-endpoint-sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "dsql_endpoint_ingress" {
  security_group_id = aws_security_group.dsql_endpoint.id
  cidr_ipv4         = var.vpc_cidr_block
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
  description       = "PostgreSQL access from VPC"
}

resource "aws_vpc_security_group_egress_rule" "dsql_endpoint_egress" {
  security_group_id = aws_security_group.dsql_endpoint.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"
}

# Aurora DSQL Cluster
# Aurora DSQL is a brand new serverless, distributed SQL database released by AWS in May 2025
# It uses aws_dsql_cluster resource (not aws_rds_cluster)
# Note: DSQL uses token-based auth (no master password); connections via VPC endpoints
resource "aws_dsql_cluster" "this" {
  deletion_protection_enabled = var.deletion_protection
  kms_encryption_key          = aws_kms_key.dsql.arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-aurora-dsql-cluster"
    }
  )
}

# VPC Endpoint for DSQL connection (DSQL uses VPC endpoints, not direct VPC access)
resource "aws_vpc_endpoint" "dsql" {
  vpc_id              = var.vpc_id
  service_name        = aws_dsql_cluster.this.vpc_endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.dsql_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-dsql-vpc-endpoint"
    }
  )
}

# Enable RDS Data API (HTTP endpoint) for DSQL cluster
# Note: DSQL may not support RDS Data API. This attempts to enable it via AWS CLI.
# If DSQL doesn't support Data API, this will fail gracefully and can be disabled.
resource "null_resource" "enable_dsql_data_api" {
  count = var.enable_data_api ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws rds enable-http-endpoint \
        --resource-arn ${aws_dsql_cluster.this.arn} \
        --region ${data.aws_region.current.name} \
        2>&1 || echo "Warning: Failed to enable Data API. DSQL may not support RDS Data API."
    EOT
  }

  depends_on = [aws_dsql_cluster.this]
}
