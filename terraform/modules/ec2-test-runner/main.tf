# EC2 Test Runner Module
# Creates an EC2 instance for testing DSQL connector from inside the VPC
# Uses SSM Session Manager for access (no inbound ports)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get latest Amazon Linux 2023 AMI (ARM64 for Graviton/m6g instances)
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

# IAM Role for EC2 instance
resource "aws_iam_role" "test_runner" {
  name = "${var.project_name}-dsql-test-runner-role"

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

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.test_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy for DSQL database authentication (IAM database user)
# DSQL uses dsql:DbConnect action, not rds-db:connect
resource "aws_iam_role_policy" "dsql_auth" {
  name = "${var.project_name}-dsql-test-runner-dsql-auth"
  role = aws_iam_role.test_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect"
        ]
        Resource = "arn:aws:dsql:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.aurora_dsql_cluster_resource_id}"
      }
    ]
  })
}

# IAM policy for DSQL admin access (to create users and schema)
resource "aws_iam_role_policy" "dsql_admin" {
  name = "${var.project_name}-dsql-test-runner-dsql-admin"
  role = aws_iam_role.test_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
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
  name  = "${var.project_name}-dsql-test-runner-kms-decrypt"
  role  = aws_iam_role.test_runner.id

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

# IAM policy for S3 read/write access (to download deployment packages and upload test results)
resource "aws_iam_role_policy" "s3_access" {
  count = var.s3_bucket_name != "" ? 1 : 0
  name  = "${var.project_name}-dsql-test-runner-s3-access"
  role  = aws_iam_role.test_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
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
resource "aws_iam_instance_profile" "test_runner" {
  name = "${var.project_name}-dsql-test-runner-profile"
  role = aws_iam_role.test_runner.name

  tags = var.tags
}

# Security Group for EC2 instance
resource "aws_security_group" "test_runner" {
  name        = "${var.project_name}-dsql-test-runner-sg"
  description = "Security group for DSQL test runner EC2 instance"
  vpc_id      = var.vpc_id

  # No ingress rules - access via SSM only

  egress {
    description = "Allow outbound to DSQL (PostgreSQL port)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow HTTPS outbound (for SSM, package installs, etc.)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTP outbound (for package installs)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow Kafka/Confluent Cloud outbound (port 9092)"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-dsql-test-runner-sg"
    }
  )
}

# EC2 Instance
resource "aws_instance" "test_runner" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  subnet_id     = var.private_subnet_id

  iam_instance_profile   = aws_iam_instance_profile.test_runner.name
  vpc_security_group_ids = [aws_security_group.test_runner.id]

  # User data to install Java 21, Maven, Docker, PostgreSQL client, Git, and AWS CLI
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    dnf update -y
    
    # Install Java 21 (LTS - Amazon Corretto), Maven, Docker, PostgreSQL client, Git
    dnf install -y java-21-amazon-corretto-devel maven docker postgresql16 git unzip python3 python3-pip
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    
    # Set Java 21 as default
    alternatives --set java /usr/lib/jvm/java-21-amazon-corretto/bin/java || true
    
    # Install Python packages for validation
    pip3 install --upgrade pip
    pip3 install asyncpg boto3 botocore
    
    # Log completion
    echo "Test runner EC2 setup complete at $(date)" >> /var/log/test-runner-setup.log
    echo "Java version:" >> /var/log/test-runner-setup.log
    java -version >> /var/log/test-runner-setup.log 2>&1
  EOF

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-dsql-test-runner"
    }
  )
}
