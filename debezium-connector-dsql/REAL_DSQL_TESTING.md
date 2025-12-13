# Testing Against the Real Aurora DSQL Cluster

This doc describes how to run **real end-to-end tests** of the connector against the DSQL cluster created by this repo’s Terraform.

## Cluster details from Terraform (current state)

These values come from your Terraform state/outputs:

- **Region**: `us-east-1` (from `terraform/terraform.tfvars`)
- **Database name**: `car_entities` (from `terraform/terraform.tfvars`)
- **IAM DB user**: `lambda_dsql_user` (from `terraform/terraform.tfvars`)
- **Port**: `5432` (Terraform output `aurora_dsql_port`)
- **DSQL endpoint (VPC endpoint DNS)**: Terraform output `aurora_dsql_endpoint`
  - Example current value: `vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com`
- **DSQL cluster “resource id” output**: Terraform output `aurora_dsql_cluster_resource_id`
  - Example current value: `vftmkydwxvxys6asbsc6ih2the`

### Important: this endpoint is **not reachable from a typical laptop**

Terraform is creating an **Interface VPC endpoint** for DSQL inside:

- **VPC**: `vpc-0f5f7a8604068f29f` (CIDR `10.0.0.0/16`)
- **Private subnets** (examples):
  - `subnet-029b45c30698fae62` (us-east-1a)
  - `subnet-06e785bf1e04c733f` (us-east-1b)

To run real tests you must execute them **from inside that VPC** (EC2/ECS/EKS, or a laptop connected via VPN/DirectConnect into that VPC).

## Recommended test execution environment

### Option A (recommended): ephemeral EC2 in the Terraform VPC

1. Launch a small EC2 instance in `vpc-0f5f7a8604068f29f` in a **private subnet**.
2. Ensure the instance has an IAM role with:
   - permissions to generate IAM DB auth tokens
   - `rds-db:connect` permissions to the DSQL resource id
3. Run the smoke tests and connector E2E tests from that instance.

### Option B: VPN into the VPC from your laptop

If you already have a VPN/Client VPN into `vpc-0f5f7a8604068f29f`, you can run the tests locally.

## Smoke test: validate IAM auth and connectivity

Run these from *inside* the VPC:

1. Fetch outputs:

```bash
cd terraform
export DSQL_ENDPOINT="$(terraform output -raw aurora_dsql_endpoint)"
export DSQL_PORT="$(terraform output -raw aurora_dsql_port)"
export DSQL_RESOURCE_ID="$(terraform output -raw aurora_dsql_cluster_resource_id)"
export DSQL_DB="car_entities"
export DSQL_USER="lambda_dsql_user"
export AWS_REGION="us-east-1"
```

2. Create a token:

```bash
TOKEN="$(aws rds generate-db-auth-token --hostname "$DSQL_ENDPOINT" --port "$DSQL_PORT" --username "$DSQL_USER" --region "$AWS_REGION")"
```

3. Connect:

```bash
psql "host=$DSQL_ENDPOINT port=$DSQL_PORT dbname=$DSQL_DB user=$DSQL_USER password=$TOKEN sslmode=require" -c "select 1;"
```

If the above fails, the connector will not work until IAM auth/networking is fixed.

## Connector E2E tests (manual but comprehensive)

### 1) Schema / prerequisites test

Validate the required table exists and has the expected columns:

- `event_headers(id, event_name, event_type, created_date, saved_date, header_data)`
- `saved_date` must be a monotonically increasing “change tracking” timestamp for correctness.

### 2) Insert-only CDC correctness (matches current connector semantics)

1. Start Kafka Connect with the connector deployed.
2. Insert N rows into `event_headers`.
3. Assert:
   - exactly N Kafka messages produced
   - each message contains:
     - correct columns
     - `__op == "c"`
     - `__table == "event_headers"`
     - `__ts_ms` present
   - ordering is non-decreasing by `saved_date`

### 3) Offset/resume tests

1. Let the connector process rows up to timestamp T.
2. Stop the connector.
3. Insert more rows with `saved_date > T`.
4. Restart connector.
5. Assert:
   - no duplicates
   - no gaps
   - offsets advance

### 4) Batch boundary tests

Set `dsql.batch.size = 10`.

1. Insert 25 rows.
2. Assert connector emits 25 rows over multiple polls.

### 5) Backfill/startup test

Start the connector with **no existing offsets**.

1. Ensure table already contains rows.
2. Start connector.
3. Confirm it captures the existing rows (current implementation behaves as “initial backfill” via `saved_date > NULL` logic).

### 6) Failure handling tests

- **Token expiry**: keep the connector running past 15 minutes and ensure it continues producing (new connections must authenticate successfully).
- **DB restart / transient network issues**: simulate a short outage, verify the task recovers and continues.

### 7) Multi-AZ / endpoint failover tests (within same region)

Terraform state shows multiple DNS entries for the VPCE, including AZ-specific ones.

You can optionally configure:
- `dsql.endpoint.primary`: the “generic” VPCE DNS
- `dsql.endpoint.secondary`: one of the AZ-specific DNS names

Then simulate endpoint issues (e.g., NACL/SG changes) and confirm the task fails over.

## Performance tests (pragmatic)

1. Insert at a controlled rate (e.g., 100/s, 1k/s).
2. Measure:
   - end-to-end latency to Kafka
   - connector CPU/memory
   - DB load
3. Tune:
   - `dsql.poll.interval.ms`
   - `dsql.batch.size`


