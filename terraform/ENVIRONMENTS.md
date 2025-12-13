# Environment Configuration Guide

This document describes the different environment configurations available in Terraform.

## Available Environments

### `dev` - Absolute Minimum Infrastructure
**Purpose**: Development environment with minimal cost

**Configuration**:
- **CloudWatch Logs Retention**: 1 day (minimum)
- **Aurora Backup Retention**: 1 day (minimum)
- **RDS Proxy**: Disabled (to minimize infrastructure)
- **Aurora Auto-Start/Stop Lambdas**: Disabled (not needed for dev)
- **Instance Class**: `db.t3.small` (smallest available)
- **Lambda Memory**: 256 MB (default)
- **Lambda Timeout**: 15 seconds (default)

**Use Case**: Personal development, quick testing, minimal cost

**Cost Optimization**: Maximum cost savings - only essential infrastructure

---

### `test` - Cost-Optimized Defaults
**Purpose**: Testing and staging environments

**Configuration**:
- **CloudWatch Logs Retention**: 3 days
- **Aurora Backup Retention**: 3 days
- **RDS Proxy**: Enabled (if `enable_rds_proxy = true`)
- **Aurora Auto-Start/Stop Lambdas**: Enabled (for cost savings)
- **Instance Class**: `db.t3.small` (default, can be upgraded)
- **Lambda Memory**: 256 MB (default)
- **Lambda Timeout**: 15 seconds (default)

**Use Case**: Integration testing, staging, QA environments

**Cost Optimization**: Balanced between cost and functionality

---

### `staging` - Pre-Production
**Purpose**: Pre-production environment matching production closely

**Configuration**:
- **CloudWatch Logs Retention**: 3 days (can be increased)
- **Aurora Backup Retention**: 3 days (can be increased)
- **RDS Proxy**: Enabled (recommended)
- **Aurora Auto-Start/Stop Lambdas**: Enabled (for cost savings)
- **Instance Class**: Can be upgraded from `db.t3.small`
- **Lambda Memory**: Can be increased based on needs
- **Lambda Timeout**: Can be increased based on needs

**Use Case**: Pre-production testing, performance testing

**Cost Optimization**: Similar to test, but can be scaled up

---

### `prod` - Production
**Purpose**: Production environment with conservative settings

**Configuration**:
- **CloudWatch Logs Retention**: 7 days (minimum for production)
- **Aurora Backup Retention**: 7 days (minimum for production)
- **RDS Proxy**: Enabled (recommended for high concurrency)
- **Aurora Auto-Start/Stop Lambdas**: Disabled (production should always be available)
- **Instance Class**: Typically larger (e.g., `db.r5.large` or higher)
- **Lambda Memory**: Typically higher (512 MB or more)
- **Lambda Timeout**: Typically higher (30+ seconds)

**Use Case**: Production workloads

**Cost Optimization**: Reliability and performance over cost

---

## Environment Selection

Set the environment in `terraform.tfvars`:

```hcl
environment = "dev"  # or "test", "staging", "prod"
```

## Overriding Defaults

You can override environment-based defaults by explicitly setting variables:

```hcl
environment = "dev"
cloudwatch_logs_retention_days = 3  # Override default 1 day
backup_retention_period = 3         # Override default 1 day
```

## Cost Comparison

| Environment | Monthly Cost Estimate* | Notes |
|------------|----------------------|-------|
| `dev` | ~$50-100 | Minimal infrastructure, 1-day retention |
| `test` | ~$100-200 | Standard testing setup, 3-day retention |
| `staging` | ~$150-300 | Can be scaled up for performance testing |
| `prod` | ~$300-1000+ | Depends on instance size and traffic |

*Cost estimates are approximate and depend on usage, instance sizes, and traffic patterns.

## Migration Between Environments

To migrate from one environment to another:

1. Update `environment` in `terraform.tfvars`
2. Optionally override specific settings (e.g., `backup_retention_period`)
3. Run `terraform plan` to see changes
4. Run `terraform apply` to apply changes

**Note**: Changing backup retention or log retention will not affect existing backups/logs, only new ones going forward.

