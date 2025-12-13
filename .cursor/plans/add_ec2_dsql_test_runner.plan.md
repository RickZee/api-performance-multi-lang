# Add EC2 DSQL Test Runner (SSM, private subnet)

## Goal

Provision an **EC2 test-runner instance inside the Terraform-created VPC** so we can run the DSQL connector tests *from inside the VPC* (required to reach the DSQL Interface VPC endpoint DNS), with:

- **No inbound ports** (SSM Session Manager access)
- **Private subnet placement**
- IAM permissions to:
  - connect to DSQL via IAM DB auth (`rds-db:connect`)
  - manage via SSM (`AmazonSSMManagedInstanceCore`)
- Reliable SSM connectivity from private subnets **without NAT** by adding **SSM interface VPC endpoints**.

## Why this is needed

Terraform output `aurora_dsql_endpoint` is a **VPC endpoint DNS** (e.g. `vpce-....vpce.amazonaws.com`), which is **not reachable from a laptop** unless you’re on a VPN/DirectConnect into the VPC. An EC2 instance in the same VPC can reach it.

## What we will change

### 1) Add Terraform module: EC2 test runner

Create module `terraform/modules/ec2-test-runner/` that provisions:

- `aws_instance` (Amazon Linux 2023, t3.small by default)
- `aws_iam_role` + `aws_iam_instance_profile`
  - attach AWS-managed policy: `AmazonSSMManagedInstanceCore`
  - attach inline policy: `rds-db:connect` to:
    - `arn:aws:rds-db:${var.aws_region}:${account_id}:dbuser:${var.aurora_dsql_cluster_resource_id}/${var.iam_database_user}`
- `aws_security_group` for the instance
  - no ingress
  - egress:
    - TCP 5432 to VPC CIDR (DSQL access)
    - TCP 443 to VPC endpoints/SSM (and generally)

Module inputs:

- `project_name`
- `vpc_id`
- `private_subnet_id` (one subnet)
- `vpc_cidr_block`
- `instance_type` (default `t3.small`)
- `iam_database_user`
- `aurora_dsql_cluster_resource_id`
- `aws_region`

Module outputs:

- `instance_id`
- `private_ip`
- `ssm_managed_instance_hint` (just instance id; SSM uses it)

### 2) Add Terraform module: SSM VPC endpoints (to avoid NAT dependency)

Create module `terraform/modules/ssm-endpoints/` that provisions **interface endpoints** in the VPC private subnets:

- `com.amazonaws.${region}.ssm`
- `com.amazonaws.${region}.ssmmessages`
- `com.amazonaws.${region}.ec2messages`

With:

- endpoint SG allowing **TCP 443 ingress** from VPC CIDR
- `private_dns_enabled = true`

This ensures SSM works from private subnets even when NAT is disabled (your `terraform.tfvars` has `enable_nat_gateway=false`).

### 3) Wire modules into `terraform/main.tf`

Add:

- `variable "enable_dsql_test_runner_ec2" { default = true/false }`
- instantiate `module "ssm_endpoints"` when enabled and when using the Terraform-created VPC (`module.vpc[0]`)
- instantiate `module "dsql_test_runner_ec2"` when enabled

Choose subnet: `module.vpc[0].private_subnet_ids[0]`.

### 4) Add outputs in `terraform/outputs.tf`

Expose:

- `dsql_test_runner_instance_id`
- `dsql_test_runner_private_ip`

## Post-provision: how you’ll use it (test workflow)

1. `terraform apply`
2. Connect via SSM:
```bash
aws ssm start-session --target <instance-id> --region us-east-1
```

3. On the instance:

   - install Java 17, git, psql, awscli (or we can add minimal `user_data` to do it automatically)
   - run the smoke tests described in `debezium-connector-dsql/REAL_DSQL_TESTING.md`
   - optionally run Kafka Connect + this connector from inside the VPC

## Files touched

- Add: `terraform/modules/ec2-test-runner/{main.tf,variables.tf,outputs.tf}`
- Add: `terraform/modules/ssm-endpoints/{main.tf,variables.tf,outputs.tf}`
- Update: `terraform/main.tf`
- Update: `terraform/variables.tf`
- Update: `terraform/outputs.tf`

## Acceptance criteria

- Terraform applies successfully
- EC2 appears as “Managed instance” in SSM (or `aws ssm describe-instance-information`)
- From the EC2, `psql` can connect to `terraform output -raw aurora_dsql_endpoint` using an IAM token