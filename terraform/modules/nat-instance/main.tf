# NAT Instance Module
# Creates an EC2 instance configured as a NAT gateway alternative
# Cost: ~$3-6/month vs $32.40/month for NAT Gateway (for low-traffic scenarios)
# 
# ⚠️ Trade-offs:
# - Requires manual management (no auto-scaling)
# - Single point of failure (unless using multiple instances)
# - Requires security group and route table management
# - Best for dev/test environments with low traffic

data "aws_region" "current" {}
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Elastic IP for NAT Instance
resource "aws_eip" "nat_instance" {
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-instance-eip"
    }
  )
}

# Security Group for NAT Instance
resource "aws_security_group" "nat_instance" {
  name        = "${var.project_name}-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = var.vpc_id

  # Allow inbound from private subnets
  ingress {
    description = "Allow all traffic from private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidrs
  }

  # Allow outbound to internet
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-instance-sg"
    }
  )
}

# IAM Role for NAT Instance (for CloudWatch Logs, SSM)
resource "aws_iam_role" "nat_instance" {
  name = "${var.project_name}-nat-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "nat_instance" {
  name = "${var.project_name}-nat-instance-profile"
  role = aws_iam_role.nat_instance.name

  tags = var.tags
}

# NAT Instance User Data Script
# Configures the instance to act as a NAT gateway
locals {
  nat_user_data = <<-EOF
#!/bin/bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

# Configure iptables for NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# Make iptables rules persistent
yum install -y iptables-services
systemctl enable iptables
service iptables save

# Disable source/destination check (required for NAT)
# This will be done via AWS CLI after instance starts
EOF
}

# NAT Instance
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  associate_public_ip_address = true
  source_dest_check           = false # Required for NAT functionality
  iam_instance_profile        = aws_iam_instance_profile.nat_instance.name

  user_data = local.nat_user_data

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-nat-instance"
    }
  )
}

# Associate Elastic IP with NAT Instance
resource "aws_eip_association" "nat_instance" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat_instance.id
}

# Disable source/destination check via AWS CLI (after instance starts)
# Note: This is done via null_resource and local-exec since source_dest_check
# attribute may not be sufficient in all cases
resource "null_resource" "disable_source_dest_check" {
  depends_on = [aws_instance.nat]

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 modify-instance-attribute \
        --instance-id ${aws_instance.nat.id} \
        --no-source-dest-check \
        --region ${data.aws_region.current.name}
    EOT
  }

  triggers = {
    instance_id = aws_instance.nat.id
  }
}


