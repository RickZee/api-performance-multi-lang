# NAT Gateway vs IPv6: Why We Need NAT

## The Problem

The EC2 instance in the private subnet needs internet access to:
1. **Install packages** (postgresql, k6) from public repositories
2. **Access AWS APIs** (for DSQL tokens, S3, etc.)
3. **Download files** from the internet

## IPv6 vs IPv4

### IPv6 (Already Enabled)
- ✅ Provides **direct internet access** from private subnets (no NAT needed)
- ✅ Works for services that support IPv6
- ❌ **Many services still only support IPv4**:
  - Most Linux package repositories (dnf/yum)
  - Some AWS services
  - Many third-party tools

### NAT Gateway (IPv4)
- ✅ Provides IPv4 internet access from private subnets
- ✅ Works with **all services** (IPv4 and IPv6)
- ❌ **Costs ~$32/month** + data transfer costs
- ❌ Adds latency for outbound connections

## Why We Enabled NAT

The EC2 instance was **failing to install packages** because:
1. Package repositories (dnf/yum) primarily use **IPv4**
2. Even with IPv6 enabled, if a service doesn't support IPv6, it won't work
3. The EC2 instance needs IPv4 access for package installation

## Alternatives to NAT

### Option 1: Use VPC Endpoints (Recommended for AWS Services)
- ✅ **Free** (no data transfer charges within same region)
- ✅ **Lower latency** (stays within AWS network)
- ✅ Works for: S3, SSM, DSQL, EC2 APIs, etc.
- ❌ **Doesn't help with public package repositories**

### Option 2: Pre-install Packages in AMI
- ✅ No NAT needed
- ✅ Faster instance startup
- ❌ Less flexible (need to rebuild AMI for updates)

### Option 3: Use Public Subnet for EC2
- ✅ No NAT needed
- ✅ Direct internet access
- ❌ Less secure (instance has public IP)

### Option 4: Use IPv6 + Accept Limitations
- ✅ No NAT costs
- ❌ Some services won't work (IPv4-only)
- ❌ Package installation may fail

## Current Setup

We have:
- ✅ **IPv6 enabled** - for IPv6 internet access
- ✅ **SSM VPC Endpoints** - for SSM access (already configured)
- ⚠️ **NAT Gateway** - temporarily enabled for package installation

## Recommendation

For the **dev environment** (cost optimization):
1. **Keep NAT disabled** (`enable_nat_gateway = false`)
2. **Use VPC endpoints** for AWS services (S3, SSM, DSQL)
3. **Pre-install packages** in the EC2 AMI or use a different approach
4. **Accept that some IPv4-only services won't work**

For the **test environment** (functionality over cost):
1. **Enable NAT Gateway** for full internet access
2. **Use VPC endpoints** for AWS services (better performance)
3. **IPv6 enabled** for dual-stack support

## What We Should Do

Since this is a **dev environment** with minimal infrastructure:
1. **Disable NAT Gateway** (revert the change)
2. **Use VPC endpoints** for AWS services (S3, SSM, DSQL)
3. **Manually install packages** via SSM Session Manager (you can copy files via S3)
4. **Or use a pre-built AMI** with packages already installed

The slow package installation was likely due to:
- IPv6-only connectivity (some repos don't support it)
- Or DNS resolution issues
- Not necessarily requiring NAT

