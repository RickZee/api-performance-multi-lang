# NAT Gateway Cost Optimization Guide

## Overview

This guide documents the NAT Gateway cost optimization implementation, which can save **$32-52/month** by leveraging IPv6 and VPC endpoints instead of NAT Gateway.

## Current Cost Analysis

**NAT Gateway Costs** (us-east-1):
- Base charge: **$32.40/month** per NAT Gateway
- Data processing: **$0.045/GB**
- **Total for producer-api**: ~$32.41/month (based on actual usage: ~0.16 GB/month)

**AWS Usage Data**:
- Data transferred in last 30 days: ~0.16 GB total
- Daily usage: Mostly 0 GB/day
- **Conclusion**: NAT Gateway is barely being used and likely not needed

## Implementation Summary

### Phase 1: Analysis ✅
- Analyzed NAT Gateway usage via CloudWatch metrics
- Identified minimal usage (~0.16 GB/month)
- Verified IPv6 is enabled

### Phase 2: VPC Endpoint Expansion ✅
Created new VPC endpoint modules to reduce NAT Gateway dependency:

1. **CloudWatch Logs Endpoint** (`terraform/modules/cloudwatch-logs-endpoint/`)
   - Enables Lambda functions to send logs without NAT Gateway
   - Automatically enabled when Lambda functions are in VPC

2. **ECR Endpoint** (`terraform/modules/ecr-endpoint/`)
   - Enables pulling Docker images from ECR without NAT Gateway
   - Automatically enabled when EC2 instances (bastion/test runner) are deployed

3. **Secrets Manager Endpoint** (`terraform/modules/secrets-manager-endpoint/`)
   - Enables accessing secrets from private subnets without NAT Gateway
   - Automatically enabled when Lambda functions or EC2 instances are deployed

**Existing Endpoints**:
- S3 Gateway endpoint (free, already configured)
- SSM Interface endpoints (already configured)

### Phase 3: Documentation & Warnings ✅
- Updated `terraform/variables.tf` with cost warnings for `enable_nat_gateway`
- Added cost documentation to `terraform/modules/vpc/main.tf`
- Updated `terraform/terraform.tfvars` with recommendations

### Phase 4: NAT Instance Alternative ✅
Created optional NAT Instance module (`terraform/modules/nat-instance/`) for low-traffic scenarios:
- Cost: ~$3-6/month vs $32.40/month for NAT Gateway
- Best for: Dev/test environments with predictable, low traffic
- Trade-offs: Requires manual management, single point of failure

## How to Disable NAT Gateway

### Step 1: Verify Requirements
Before disabling, verify:
1. IPv6 is enabled (`enable_ipv6 = true`) ✅ Already enabled
2. VPC endpoints are configured ✅ Already configured
3. Required services support IPv6 (GitHub, Confluent Cloud)

### Step 2: Update Configuration
In `terraform/terraform.tfvars`:

```hcl
# Disable NAT Gateway
enable_nat_gateway = false
```

### Step 3: Apply Changes
```bash
cd terraform
terraform plan  # Review changes
terraform apply # Apply changes
```

### Step 4: Verify Functionality
Test that all services still work:
- Lambda functions can send logs to CloudWatch
- EC2 instances can access required services
- All AWS service calls work via VPC endpoints or IPv6

## Cost Savings

| Scenario | Monthly Cost | Savings |
|----------|-------------|---------|
| **Current (with NAT Gateway)** | $32.41 | - |
| **After optimization (IPv6 + VPC endpoints)** | $0 | **$32.41/month** |
| **With NAT Instance (if needed)** | $3-6 | **$26-29/month** |

**Annual Savings**: $388-624/year

## VPC Endpoints Created

The following VPC endpoints are automatically created when relevant resources are enabled:

| Endpoint | Type | Cost | When Enabled |
|----------|------|------|--------------|
| S3 | Gateway | Free | When bastion host is enabled |
| SSM | Interface | ~$7/month | When EC2 instances are in private subnets |
| CloudWatch Logs | Interface | ~$7/month | When Lambda functions are in VPC |
| ECR API | Interface | ~$7/month | When EC2 instances are deployed |
| ECR DKR | Interface | ~$7/month | When EC2 instances are deployed |
| Secrets Manager | Interface | ~$7/month | When Lambda/EC2 need secrets |

**Note**: Interface endpoints have hourly charges (~$0.01/hour per endpoint) but eliminate NAT Gateway data processing costs. For low-traffic scenarios, they're typically cheaper than NAT Gateway.

## Troubleshooting

### Issue: Services can't access internet after disabling NAT Gateway

**Solution**:
1. Verify IPv6 is enabled: `enable_ipv6 = true`
2. Check VPC endpoints are created: `terraform output`
3. Verify security groups allow IPv6 traffic
4. Test IPv6 connectivity from EC2 instances

### Issue: Lambda functions can't send logs

**Solution**:
1. Verify CloudWatch Logs endpoint is created
2. Check Lambda security group allows outbound HTTPS (443)
3. Verify Lambda is in VPC with proper subnet configuration

### Issue: EC2 instances can't pull Docker images

**Solution**:
1. Verify ECR endpoints are created
2. Check EC2 security group allows outbound HTTPS (443)
3. Verify EC2 IAM role has ECR permissions

## Alternative: NAT Instance

If you still need NAT Gateway functionality but want to reduce costs:

1. **Enable NAT Instance module** in `terraform/main.tf`:
```hcl
module "nat_instance" {
  count  = var.enable_nat_instance && !var.enable_nat_gateway ? 1 : 0
  source = "./modules/nat-instance"
  
  project_name         = var.project_name
  vpc_id               = module.vpc[0].vpc_id
  public_subnet_id     = module.vpc[0].public_subnet_ids[0]
  private_subnet_cidrs = module.vpc[0].private_subnet_cidrs
  instance_type        = "t4g.nano"  # ARM-based for cost savings
  
  tags = local.common_tags
}
```

2. **Update route tables** to use NAT instance instead of NAT Gateway

**Cost Comparison**:
- NAT Gateway: $32.40/month
- NAT Instance (t4g.nano): ~$3/month
- **Savings**: ~$29/month

## References

- [AWS NAT Gateway Pricing](https://aws.amazon.com/vpc/pricing/)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [IPv6 on AWS](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-migrate-ipv6.html)

## Next Steps

1. **Test disabling NAT Gateway** in dev environment
2. **Monitor CloudWatch metrics** to verify no service disruptions
3. **Review VPC Flow Logs** (if enabled) to understand traffic patterns
4. **Consider NAT Instance** if IPv6/VPC endpoints don't cover all use cases

