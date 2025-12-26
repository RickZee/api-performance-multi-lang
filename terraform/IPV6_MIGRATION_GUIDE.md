# IPv6 Migration Guide - Eliminate NAT Gateway

## Overview

This guide explains how to migrate the entire project to use IPv6 exclusively, eliminating the need for NAT Gateway and saving **$32.40/month**.

## Current IPv6 Status ✅

**Already Configured**:
- ✅ VPC has IPv6 enabled (`enable_ipv6 = true`)
- ✅ Public and private subnets have IPv6 CIDR blocks
- ✅ Private subnets route IPv6 traffic through Internet Gateway (no NAT needed)
- ✅ Aurora security groups have IPv6 egress rules
- ✅ Lambda security groups have IPv6 egress rules (for Aurora access)

**Needs IPv6 Support**:
- ⚠️ EC2 security groups (bastion, test runner) - currently IPv4 only for internet access
- ⚠️ Lambda security groups - need IPv6 for general internet access (beyond Aurora)

## Services That Need Internet Access

### 1. EC2 Instances (Bastion Host & Test Runner)
**Current**: IPv4 only for HTTPS/HTTP (GitHub, package repositories)
**Needs**: IPv6 egress rules for HTTPS/HTTP

**Services Accessed**:
- GitHub (✅ Supports IPv6)
- Package repositories (✅ Most support IPv6)
- AWS APIs (✅ Use VPC endpoints or IPv6)

### 2. Lambda Functions
**Current**: IPv6 only for Aurora access
**Needs**: IPv6 egress for general internet (if needed)

**Services Accessed**:
- CloudWatch Logs (✅ Use VPC endpoint - already configured)
- AWS APIs (✅ Use VPC endpoints or IPv6)
- External APIs (✅ Most support IPv6)

### 3. Confluent Cloud
**Current**: Connects to Aurora (inbound, not outbound from VPC)
**Status**: ✅ No changes needed (inbound connection)

## Implementation Steps

### Step 1: Add IPv6 Egress Rules to EC2 Security Groups

#### Bastion Host Security Group
Add IPv6 egress rules for HTTPS/HTTP:

```hcl
# In terraform/modules/bastion-host/main.tf

# IPv6 egress for HTTPS (if IPv6 is enabled)
dynamic "egress" {
  for_each = var.enable_ipv6 ? [1] : []
  content {
    description      = "Allow HTTPS outbound (IPv6)"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
}

# IPv6 egress for HTTP (if IPv6 is enabled)
dynamic "egress" {
  for_each = var.enable_ipv6 ? [1] : []
  content {
    description      = "Allow HTTP outbound (IPv6)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
}
```

#### Test Runner Security Group
Add IPv6 egress rules for HTTPS/HTTP:

```hcl
# In terraform/modules/ec2-test-runner/main.tf

# IPv6 egress for HTTPS (if IPv6 is enabled)
dynamic "egress" {
  for_each = var.enable_ipv6 ? [1] : []
  content {
    description      = "Allow HTTPS outbound (IPv6)"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
}

# IPv6 egress for HTTP (if IPv6 is enabled)
dynamic "egress" {
  for_each = var.enable_ipv6 ? [1] : []
  content {
    description      = "Allow HTTP outbound (IPv6)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }
}
```

### Step 2: Add IPv6 Egress Rules to Lambda Security Group

Add general IPv6 internet access for Lambda functions (if needed):

```hcl
# In terraform/main.tf, update aws_security_group.lambda

# IPv6 egress for general internet access (if IPv6 is enabled)
dynamic "egress" {
  for_each = (var.enable_aurora || var.enable_aurora_dsql_cluster) && try(module.vpc[0].vpc_ipv6_cidr_block != null, false) ? [1] : []
  content {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound (IPv6) - for internet access"
  }
}
```

**Note**: Lambda functions should primarily use VPC endpoints for AWS services. This rule is for external APIs if needed.

### Step 3: Verify VPC Endpoints Are Used

Ensure all AWS service calls use VPC endpoints:
- ✅ S3 (Gateway endpoint - free)
- ✅ SSM (Interface endpoints - for EC2)
- ✅ CloudWatch Logs (Interface endpoint - for Lambda)
- ✅ ECR (Interface endpoints - for EC2)
- ✅ Secrets Manager (Interface endpoint - for Lambda/EC2)

### Step 4: Disable NAT Gateway

Once IPv6 is fully configured:

```hcl
# In terraform/terraform.tfvars
enable_nat_gateway = false
```

### Step 5: Test IPv6 Connectivity

#### Test from EC2 Instance (Bastion or Test Runner)

```bash
# Test IPv6 connectivity to GitHub
curl -6 https://github.com

# Test IPv6 DNS resolution
dig AAAA github.com

# Test package installation over IPv6
# Most package managers (yum, apt) will prefer IPv6 if available
```

#### Test Lambda Functions

```bash
# Test Lambda can access external APIs over IPv6
# (if your Lambda functions need external API access)
```

## IPv6 Support Status

### ✅ Fully IPv6 Compatible
- **GitHub**: Dual-stack (IPv4 + IPv6)
- **AWS Services**: All support IPv6 or have VPC endpoints
- **Most Package Repositories**: Support IPv6

### ⚠️ May Need IPv4 (Use VPC Endpoints Instead)
- **Confluent Cloud**: Check IPv6 support (likely supports IPv6)
- **Some Legacy APIs**: May be IPv4-only (use VPC endpoints or NAT64 if needed)

### 🔍 Services to Verify
1. **Confluent Cloud**: Check if egress IPs support IPv6
2. **Any Custom APIs**: Verify IPv6 support

## NAT64/DNS64 (If Needed)

If you encounter IPv4-only services that can't use VPC endpoints, AWS provides NAT64/DNS64:

- **NAT64**: Translates IPv6 to IPv4 for accessing IPv4-only services
- **DNS64**: Synthesizes AAAA records for IPv4 addresses
- **Cost**: Similar to NAT Gateway but only for IPv4-only services

**Note**: With VPC endpoints for AWS services and IPv6 for external services, NAT64 is typically not needed.

## Egress-Only Internet Gateway

For additional security, consider using an **Egress-Only Internet Gateway** instead of routing IPv6 through the Internet Gateway:

- Allows outbound IPv6 traffic
- Blocks inbound IPv6 connections from internet
- More secure than full Internet Gateway access

**Implementation**: Add to `terraform/modules/vpc/main.tf`:

```hcl
# Egress-Only Internet Gateway (for IPv6 outbound-only access)
resource "aws_egress_only_internet_gateway" "this" {
  count = var.enable_ipv6 && var.use_egress_only_igw ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eigw"
    }
  )
}

# Update private route table to use Egress-Only IGW instead of IGW
# (if use_egress_only_igw is true)
```

## Cost Comparison

| Configuration | Monthly Cost | Notes |
|--------------|-------------|-------|
| **Current (NAT Gateway)** | $32.41 | NAT Gateway + minimal data |
| **IPv6 Only** | $0 | No NAT Gateway needed |
| **IPv6 + VPC Endpoints** | ~$28-35 | Interface endpoints (~$7/month each) |
| **IPv6 + Egress-Only IGW** | $0 | More secure than IGW |

**Recommendation**: Use IPv6 + VPC endpoints. Interface endpoints are cheaper than NAT Gateway for low-to-medium traffic.

## Migration Checklist

- [ ] Add IPv6 egress rules to EC2 security groups
- [ ] Add IPv6 egress rules to Lambda security group (if needed)
- [ ] Verify all VPC endpoints are configured
- [ ] Test IPv6 connectivity from EC2 instances
- [ ] Test Lambda functions work with IPv6
- [ ] Verify Confluent Cloud supports IPv6 (or use PrivateLink)
- [ ] Disable NAT Gateway (`enable_nat_gateway = false`)
- [ ] Monitor CloudWatch metrics to verify no service disruptions
- [ ] Update documentation

## Rollback Plan

If issues occur:

1. **Re-enable NAT Gateway**: Set `enable_nat_gateway = true`
2. **Keep IPv6 enabled**: Dual-stack (IPv4 + IPv6) is safe
3. **Gradually migrate**: Test services one by one

## References

- [AWS IPv6 Support](https://docs.aws.amazon.com/vpc/latest/userguide/aws-ipv6-support.html)
- [Egress-Only Internet Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/egress-only-internet-gateway.html)
- [NAT64/DNS64](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-nat64-dns64.html)
- [GitHub IPv6](https://github.blog/2011-03-09-ipv6-support-now-available/)

