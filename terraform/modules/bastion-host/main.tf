# Bastion Host Module
# Creates an EC2 instance in a public subnet for database access
# Uses SSH key pair for access (or SSM Session Manager as fallback)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get latest Amazon Linux 2023 AMI (ARM64 for Graviton/t4g instances)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create or use existing key pair
resource "aws_key_pair" "bastion" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.project_name}-bastion-key"
  public_key = var.ssh_public_key

  tags = var.tags
}

# IAM Role for Bastion instance
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-bastion-role"

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

# Attach AWS managed policy for SSM (fallback access method)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy for DSQL database authentication
resource "aws_iam_role_policy" "dsql_auth" {
  name = "${var.project_name}-bastion-dsql-auth"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin"
        ]
        Resource = "arn:aws:dsql:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.aurora_dsql_cluster_resource_id}"
      }
    ]
  })
}

# IAM policy for KMS decrypt (required to access encrypted DSQL cluster)
resource "aws_iam_role_policy" "kms_decrypt" {
  count = var.dsql_kms_key_arn != "" ? 1 : 0
  name  = "${var.project_name}-bastion-kms-decrypt"
  role  = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.dsql_kms_key_arn
      }
    ]
  })
}

# IAM policy for S3 read access (to download deployment packages and connector JARs)
resource "aws_iam_role_policy" "s3_read" {
  count = var.s3_bucket_name != "" ? 1 : 0
  name  = "${var.project_name}-bastion-s3-read"
  role  = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = var.tags
}

# Security Group for Bastion Host
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access from anywhere (can be restricted to specific IPs)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
  }

  # Outbound to DSQL (PostgreSQL port)
  egress {
    description = "Allow outbound to DSQL (PostgreSQL port)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # Outbound HTTPS for package installs
  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTP for package installs
  egress {
    description = "Allow HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to Confluent Cloud Kafka (port 9092)
  egress {
    description = "Allow outbound to Confluent Cloud Kafka"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion-sg"
    }
  )
}

# Elastic IP for Bastion Host (optional, for consistent IP)
resource "aws_eip" "bastion" {
  count  = var.allocate_elastic_ip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion-eip"
    }
  )
}

# EC2 Instance
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  subnet_id     = var.public_subnet_id

  # Use key pair if provided, otherwise rely on SSM
  key_name = var.ssh_public_key != "" ? aws_key_pair.bastion[0].key_name : null

  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # Associate Elastic IP if requested
  associate_public_ip_address = true

  # User data to install PostgreSQL client, AWS CLI, Python 3, and validation dependencies
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    dnf update -y
    
    # Install base packages (PostgreSQL client, Git, AWS CLI, Python 3)
    dnf install -y postgresql16 git unzip python3 python3-pip
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    
    # Install Python packages for DSQL validation
    pip3 install --upgrade pip
    pip3 install asyncpg boto3 botocore
    
    # Create directory for validation scripts
    mkdir -p /opt/validation-scripts
    
    # Download validation script from S3 if available, otherwise create a placeholder
    # The script will be uploaded via SSM when needed
    cat > /opt/validation-scripts/validate_dsql_bastion.py <<'PYTHON_EOF'
# Placeholder - will be replaced by actual script via SSM
PYTHON_EOF
    
    # Set permissions
    chmod 755 /opt/validation-scripts
    chmod 644 /opt/validation-scripts/validate_dsql_bastion.py
    
    # Log completion
    echo "Bastion host setup complete at $(date)" >> /var/log/bastion-setup.log
  EOF

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion"
    }
  )
}

# Associate Elastic IP if allocated
resource "aws_eip_association" "bastion" {
  count       = var.allocate_elastic_ip ? 1 : 0
  instance_id = aws_instance.bastion.id
  allocation_id = aws_eip.bastion[0].id
}
