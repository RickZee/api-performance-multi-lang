# NAT Gateway Disable - Expected Changes

## Configuration Updated ✅

**File**: `terraform/terraform.tfvars`
- Changed: `enable_nat_gateway = false`
- Status: ✅ Configuration updated

## Expected Terraform Changes

When you run `terraform apply`, the following resources will be **destroyed**:

### Resources to be Destroyed

1. **NAT Gateway** (`aws_nat_gateway.this[0]`)
   - Resource ID: `nat-09e1a7a00f235f014`
   - This is the main cost-saving change

2. **Elastic IP** (`aws_eip.nat[0]`)
   - Allocation ID: `eipalloc-0cb83fdc17607132a`
   - Will be released (free when attached to NAT Gateway, but no longer needed)

### Resources to be Modified

1. **Private Route Table** (`aws_route_table.private[0]`)
   - Will remove IPv4 route to NAT Gateway
   - Will keep IPv6 route to Internet Gateway (no changes needed)

### Resources That Will Remain (No Changes)

- ✅ VPC and all subnets (IPv6 enabled)
- ✅ Internet Gateway (still needed for IPv6)
- ✅ All security groups (IPv6 rules already configured)
- ✅ All VPC endpoints (S3, SSM, CloudWatch Logs, ECR, Secrets Manager)
- ✅ All EC2 instances (bastion, test runner)
- ✅ All Lambda functions
- ✅ All Aurora clusters
- ✅ All other infrastructure

## Impact Assessment

### ✅ No Service Disruption Expected

**Why it's safe**:
1. **IPv6 is enabled** - All subnets have IPv6 addresses
2. **Private subnets route IPv6 through Internet Gateway** - No NAT needed
3. **VPC endpoints configured** - AWS services use endpoints (no NAT needed)
4. **Security groups have IPv6 rules** - EC2 and Lambda can use IPv6
5. **External services support IPv6** - GitHub, package repos support IPv6

### Services That Will Continue Working

| Service | How It Works Without NAT Gateway |
|---------|----------------------------------|
| **EC2 → GitHub** | IPv6 via Internet Gateway ✅ |
| **EC2 → Package Repos** | IPv6 via Internet Gateway ✅ |
| **Lambda → CloudWatch Logs** | VPC endpoint ✅ |
| **Lambda → AWS APIs** | VPC endpoints or IPv6 ✅ |
| **EC2 → S3** | VPC Gateway endpoint (free) ✅ |
| **EC2 → SSM** | VPC Interface endpoints ✅ |
| **EC2 → ECR** | VPC Interface endpoints ✅ |
| **Aurora** | VPC internal (no internet needed) ✅ |

## Cost Impact

| Item | Before | After | Change |
|------|--------|-------|--------|
| NAT Gateway | $32.40/month | $0/month | **-$32.40/month** |
| Elastic IP | $0/month (attached) | $0/month (released) | $0 |
| Data Processing | ~$0.01/month | $0/month | **-$0.01/month** |
| **Total** | **$32.41/month** | **$0/month** | **-$32.41/month** |

**Annual Savings**: $388.92/year

## How to Apply Changes

### Step 1: Check for State Lock

If you see a state lock error, wait for any running terraform operations to complete, or:

```bash
# Check if terraform is running elsewhere
# Wait for it to complete, then proceed
```

### Step 2: Review Plan

```bash
cd terraform
terraform plan
```

**Expected output**:
- 1 resource to destroy (NAT Gateway)
- 1 resource to destroy (Elastic IP)
- 1 resource to modify (Route table - remove NAT Gateway route)

### Step 3: Apply Changes

```bash
terraform apply
```

**Expected duration**: ~2-5 minutes (NAT Gateway deletion)

### Step 4: Verify

#### Check NAT Gateway is Deleted

```bash
aws ec2 describe-nat-gateways --nat-gateway-ids nat-09e1a7a00f235f014
# Should return: "State": "deleted"
```

#### Test IPv6 Connectivity from EC2

```bash
# Connect to bastion host via SSM
aws ssm start-session --target <instance-id>

# Test IPv6 connectivity
curl -6 https://github.com
dig AAAA github.com

# Test package installation (will use IPv6)
sudo yum update -y
```

#### Verify Lambda Functions

- Check CloudWatch Logs for Lambda functions
- Verify no errors related to network connectivity
- Test API endpoints

## Rollback Plan

If you encounter issues:

### Quick Rollback

1. **Re-enable NAT Gateway** in `terraform.tfvars`:
   ```hcl
   enable_nat_gateway = true
   ```

2. **Apply changes**:
   ```bash
   terraform apply
   ```

3. **NAT Gateway will be recreated** (takes ~5 minutes)

### Why Rollback is Safe

- IPv6 remains enabled (dual-stack is safe)
- No resources are deleted except NAT Gateway
- NAT Gateway can be recreated quickly
- All other infrastructure remains unchanged

## Monitoring After Disable

### CloudWatch Metrics to Monitor

1. **NAT Gateway Metrics** (should be 0 after deletion):
   - `BytesOutToDestination`
   - `BytesInFromSource`
   - `PacketsOutToDestination`
   - `PacketsInFromSource`

2. **VPC Endpoint Metrics** (should show activity):
   - CloudWatch Logs endpoint traffic
   - ECR endpoint traffic
   - SSM endpoint traffic

3. **Lambda Metrics**:
   - Invocation count (should remain normal)
   - Error rate (should remain normal)
   - Duration (should remain normal)

### VPC Flow Logs (Optional)

Enable VPC Flow Logs to monitor IPv6 traffic:

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-0f5f7a8604068f29f \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flow-logs
```

## Troubleshooting

### Issue: EC2 Can't Access GitHub

**Solution**:
1. Verify IPv6 is enabled: `ip -6 addr show`
2. Test IPv6 connectivity: `curl -6 https://github.com`
3. Check security group has IPv6 egress rules
4. Verify route table has IPv6 route to Internet Gateway

### Issue: Lambda Can't Send Logs

**Solution**:
1. Verify CloudWatch Logs endpoint is created
2. Check Lambda security group allows outbound HTTPS (443)
3. Verify Lambda is in VPC with proper subnet configuration

### Issue: EC2 Can't Pull Docker Images

**Solution**:
1. Verify ECR endpoints are created
2. Check EC2 security group allows outbound HTTPS (443)
3. Verify EC2 IAM role has ECR permissions

## Success Criteria

✅ NAT Gateway deleted
✅ Elastic IP released
✅ Route table updated (no NAT Gateway route)
✅ EC2 instances can access internet via IPv6
✅ Lambda functions can send logs via VPC endpoint
✅ All services continue working normally
✅ No increase in error rates
✅ Cost savings confirmed in AWS Cost Explorer

## Next Steps After Successful Disable

1. **Monitor for 24-48 hours** to ensure no issues
2. **Verify cost savings** in AWS Cost Explorer
3. **Update documentation** if needed
4. **Consider disabling NAT Gateway in other environments** (if applicable)

