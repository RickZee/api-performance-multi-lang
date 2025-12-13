### Terraform Configuration for Amazon Aurora DSQL in Active-Active Multi-Region Setup

Amazon Aurora DSQL is the latest serverless, distributed SQL database service from AWS, built on Aurora technology for unlimited scalability, strong consistency, and high availability (up to 99.999% multi-region). It supports active-active deployments across regions with no single point of failure, making it ideal for your financial mortgage platform's evolution toward low-latency, resilient event processing. Unlike traditional Aurora PostgreSQL (which is single-primary or global with read replicas), DSQL enables true multi-region writes with strong consistency via decoupled transactions and Amazon Time Sync—up to 4× faster than other distributed SQL systems. It's PostgreSQL-compatible (subset of version 16 features), so your existing Spring microservices, Qlik Replicate CDC, GraphQL consumers, and Kafka integrations can migrate with minimal changes. Connections use VPC endpoints and temporary auth tokens (no master password set at creation; use 'admin' user and generate tokens via AWS SDK/CLI).

This setup deploys DSQL clusters in two regions for active-active mode: primary in `us-east-1` (writes/reads) and secondary in `us-west-2` (peered for mutual replication). Each uses the other's region as witness for quorum-based failover (no cluster in witness; just configuration). Peering is bidirectional for symmetry. DSQL is serverless—no instance sizing needed—and auto-scales based on load from your ingestion API and EMR shreds.

Key adaptations for your stack:
- **Active-Active**: Route writes/reads to local region endpoints via your EKS-hosted services (e.g., Spring/gRPC consumers). Use SDK for token-based auth with PingID integration.
- **Security**: Custom KMS encryption (Vault-managed keys), VPC endpoints with security groups allowing ingress from private subnets (tie to EKS nodes, AIM cross-account).
- **Integration**: Endpoint for PostgreSQL clients (port 5432). Test CDC with Qlik to S3/Iceberg; monitor via ELK. No database name specified at creation—create schemas post-deployment.
- **Testing**: Apply incrementally; test failover by promoting secondary via AWS CLI. Profile performance for event header/entity tables.
- **Limitations**: Limited PostgreSQL features; higher costs for replication; ensure Qlik/Dremio/Snowflake compatibility with DSQL.

Use the `hashicorp/aws` provider (v6.0+ for DSQL support). Due to mutual peering, apply in steps: `terraform apply -target=aws_dsql_cluster.primary` (creates primary without full peering), then full `terraform apply` (adds bidirectional peering).

#### versions.tf
```hcl
terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
```

#### main.tf
```hcl
provider "aws" {
  region = local.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = local.secondary_region
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "primary" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name               = "mortgage-dsql"
  primary_region     = "us-east-1"
  primary_vpc_cidr   = "10.0.0.0/16"
  primary_azs        = slice(data.aws_availability_zones.primary.names, 0, 3)
  secondary_region   = "us-west-2"
  secondary_vpc_cidr = "10.1.0.0/16"
  secondary_azs      = slice(data.aws_availability_zones.secondary.names, 0, 3)
  tags = {
    Platform    = "Mortgage-Platform"
    Environment = "prod"
  }
}

################################################################################
# DSQL Clusters
################################################################################

resource "aws_dsql_cluster" "primary" {
  deletion_protection_enabled = true
  kms_encryption_key           = aws_kms_key.primary.arn

  multi_region_properties {
    clusters       = [aws_dsql_cluster.secondary.arn]
    witness_region = local.secondary_region
  }

  tags = local.tags
}

resource "aws_dsql_cluster" "secondary" {
  provider = aws.secondary

  deletion_protection_enabled = true
  kms_encryption_key           = aws_kms_key.secondary.arn

  multi_region_properties {
    clusters       = [aws_dsql_cluster.primary.arn]
    witness_region = local.primary_region
  }

  tags = local.tags

  depends_on = [aws_dsql_cluster.primary]  # Helps with initial apply sequencing
}

################################################################################
# VPC Endpoints for Connection
################################################################################

resource "aws_vpc_endpoint" "primary" {
  vpc_id              = module.primary_vpc.vpc_id
  service_name        = aws_dsql_cluster.primary.vpc_endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.primary_vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.primary.id]
  private_dns_enabled = true

  tags = local.tags
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-primary-sg"
  description = "Security group for DSQL VPC endpoint"
  vpc_id      = module.primary_vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_ingress" {
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = module.primary_vpc.vpc_cidr_block
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

resource "aws_vpc_security_group_egress_rule" "primary_egress" {
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Secondary VPC Endpoint
resource "aws_vpc_endpoint" "secondary" {
  provider = aws.secondary

  vpc_id              = module.secondary_vpc.vpc_id
  service_name        = aws_dsql_cluster.secondary.vpc_endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.secondary_vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.secondary.id]
  private_dns_enabled = true

  tags = local.tags
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-secondary-sg"
  description = "Security group for DSQL VPC endpoint"
  vpc_id      = module.secondary_vpc.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_ingress" {
  provider = aws.secondary

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = module.secondary_vpc.vpc_cidr_block
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

resource "aws_vpc_security_group_egress_rule" "secondary_egress" {
  provider = aws.secondary

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

################################################################################
# Supporting Resources (VPC, KMS)
################################################################################

module "primary_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-primary"
  cidr = local.primary_vpc_cidr

  azs              = local.primary_azs
  private_subnets  = [for k, v in local.primary_azs : cidrsubnet(local.primary_vpc_cidr, 8, k + 3)]
  public_subnets   = [for k, v in local.primary_azs : cidrsubnet(local.primary_vpc_cidr, 8, k)]

  tags = local.tags
}

module "secondary_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  providers = { aws = aws.secondary }

  name = "${local.name}-secondary"
  cidr = local.secondary_vpc_cidr

  azs              = local.secondary_azs
  private_subnets  = [for k, v in local.secondary_azs : cidrsubnet(local.secondary_vpc_cidr, 8, k + 3)]
  public_subnets   = [for k, v in local.secondary_azs : cidrsubnet(local.secondary_vpc_cidr, 8, k)]

  tags = local.tags
}

data "aws_iam_policy_document" "kms" {
  statement {
    sid     = "Enable IAM User Permissions"
    actions = ["kms:*"]
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

resource "aws_kms_key" "primary" {
  policy = data.aws_iam_policy_document.kms.json
  tags   = local.tags
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  policy = data.aws_iam_policy_document.kms.json
  tags   = local.tags
}
```

#### outputs.tf
```hcl
output "primary_endpoint" {
  description = "Endpoint for primary DSQL cluster (route local traffic here)"
  value       = aws_dsql_cluster.primary.endpoint
}

output "primary_arn" {
  description = "ARN of primary DSQL cluster"
  value       = aws_dsql_cluster.primary.arn
}

output "primary_vpc_endpoint_dns" {
  description = "DNS name of primary VPC endpoint"
  value       = aws_vpc_endpoint.primary.dns_entry[0].dns_name
}

output "secondary_endpoint" {
  description = "Endpoint for secondary DSQL cluster"
  value       = aws_dsql_cluster.secondary.endpoint
}

output "secondary_arn" {
  description = "ARN of secondary DSQL cluster"
  value       = aws_dsql_cluster.secondary.arn
}

output "secondary_vpc_endpoint_dns" {
  description = "DNS name of secondary VPC endpoint"
  value       = aws_vpc_endpoint.secondary.dns_entry[0].dns_name
}
```

#### Next Steps for Integration and Evolution
- **Deployment**: `terraform init`, `terraform plan`, apply with `-target=aws_dsql_cluster.primary` first, then full apply to resolve peering.
- **Connection**: Use AWS SDK to generate temp tokens: `aws dsql generate-db-auth-token --endpoint <endpoint> --user admin`. Integrate with Vault for secrets.
- **Migration**: Export from existing Aurora Postgres, import to DSQL. Test CDC to data lake (S3/EMR/Iceberg).
- **Monitoring**: Enable CloudWatch for status; integrate ELK/APM for queries.
- **Failover Testing**: Use `aws dsql failover-cluster` CLI; ensure active-active routing in consumers.
- **Scaling/Cost**: Auto-scales; monitor with Snowflake for analytics. If needing more regions, add clusters with peering.

This evolves your platform to serverless distributed SQL while maintaining reliability for mortgage events. If this isn't the exact DSQL config you meant, provide more details.