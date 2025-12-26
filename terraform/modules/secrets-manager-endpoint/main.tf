# Secrets Manager VPC Endpoint Module
# Creates an interface VPC endpoint for AWS Secrets Manager
# This enables accessing secrets from private subnets without NAT Gateway

data "aws_region" "current" {}

# Security Group for Secrets Manager VPC Endpoint
resource "aws_security_group" "secrets_manager_endpoint" {
  name        = "${var.project_name}-secrets-manager-endpoint-sg"
  description = "Security group for Secrets Manager VPC endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-secrets-manager-endpoint-sg"
    }
  )
}

# Secrets Manager VPC Endpoint
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.secrets_manager_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-secrets-manager-endpoint"
    }
  )
}

