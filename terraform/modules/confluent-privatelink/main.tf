# Confluent Cloud PrivateLink Module
# Creates AWS VPC endpoint for Confluent Cloud PrivateLink connectivity

# Security Group for Confluent PrivateLink
resource "aws_security_group" "confluent_privatelink" {
  name        = "${var.project_name}-confluent-privatelink-sg"
  description = "Security group for Confluent Cloud PrivateLink VPC endpoint"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC to Confluent Cloud"
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
      Name = "${var.project_name}-confluent-privatelink-sg"
    }
  )
}

# VPC Endpoint for Confluent Cloud
resource "aws_vpc_endpoint" "confluent" {
  vpc_id             = var.vpc_id
  service_name       = var.confluent_service_name
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.confluent_privatelink.id]

  private_dns_enabled = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-confluent-privatelink-endpoint"
    }
  )
}




