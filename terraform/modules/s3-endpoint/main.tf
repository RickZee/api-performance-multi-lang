# S3 VPC Endpoint Module
# Creates a Gateway VPC endpoint for S3 (free, no data transfer charges)
# This enables S3 access from private subnets without NAT Gateway

data "aws_region" "current" {}

# S3 Gateway VPC Endpoint (free, no data transfer charges)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-s3-endpoint"
    }
  )
}

