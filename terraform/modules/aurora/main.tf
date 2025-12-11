# Aurora PostgreSQL Module
# Creates Aurora PostgreSQL cluster with logical replication enabled

# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-aurora-subnet-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora-sg"
  description = "Security group for Aurora PostgreSQL cluster"
  vpc_id      = var.vpc_id

  # Primary ingress rule: Use effective CIDR blocks (either Confluent Cloud IPs or allowed CIDRs)
  # If publicly accessible and Confluent Cloud CIDRs provided, restrict to those IPs only
  # Otherwise, use allowed_cidr_blocks (defaults to 0.0.0.0/0 for full public access)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.effective_cidr_blocks
    description = local.use_restricted_access ? "PostgreSQL access from Confluent Cloud (restricted)" : "PostgreSQL access from allowed CIDR blocks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (IPv4)"
  }

  # IPv6 egress (if IPv6 is enabled)
  dynamic "egress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
      description      = "Allow all outbound (IPv6)"
    }
  }

  tags = merge(
    var.tags,
    {
      Name                                    = "${var.project_name}-aurora-sg"
      PubliclyAccessible                      = tostring(var.publicly_accessible)
      ConfluentCloudRestricted                = tostring(local.use_restricted_access)
      "ManagedBy"                            = "Terraform"
      "Purpose"                              = "Aurora PostgreSQL for CDC streaming"
    }
  )
}

# Security Group Rules: Allow access from additional security groups (e.g., EKS node groups)
resource "aws_security_group_rule" "aurora_from_additional_sg" {
  count = length(var.additional_security_group_ids)

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.additional_security_group_ids[count.index]
  security_group_id        = aws_security_group.aurora.id
  description              = "PostgreSQL access from additional security group"
}

# Parameter Group for Aurora Cluster (enables logical replication)
resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.project_name}-aurora-cluster-pg"
  family      = var.parameter_group_family
  description = "Parameter group for Aurora PostgreSQL with logical replication"

  parameter {
    name  = "rds.logical_replication"
    value = "1"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "max_replication_slots"
    value = "10"
  }

  parameter {
    name  = "max_wal_senders"
    value = "10"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-aurora-cluster-pg"
    }
  )

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [parameter]
  }
}

# Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project_name}-aurora-cluster"

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned"

  database_name   = var.database_name
  master_username = var.database_user
  master_password = var.database_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  # Backup configuration
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Snapshot configuration
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  deletion_protection       = var.deletion_protection

  # Enable CloudWatch logs
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Storage encryption
  storage_encrypted = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-aurora-cluster"
    }
  )

  lifecycle {
    ignore_changes = [master_password]
  }
}

# Aurora Cluster Instance (Primary)
resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.project_name}-aurora-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  publicly_accessible = var.publicly_accessible

  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-aurora-instance-${count.index + 1}"
    }
  )
}
