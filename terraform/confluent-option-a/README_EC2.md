# Run Option A from EC2 (SSM)

## 1) Connect to EC2

From your laptop:

```bash
cd terraform
terraform output -raw dsql_test_runner_ssm_command | bash
```

## 2) Prepare the repo on EC2

On EC2:

```bash
cd /tmp
git clone https://github.com/rickzakharov/api-performance-multi-lang.git
cd api-performance-multi-lang
```

## 3) Create `connect.env`

On EC2:

```bash
cd /tmp/api-performance-multi-lang/terraform/confluent-option-a
cp connect.env.example connect.env
vi connect.env
```

Fill in:
- `CC_BOOTSTRAP_SERVERS`
- `CC_KAFKA_API_KEY`
- `CC_KAFKA_API_SECRET`
- `DSQL_ENDPOINT_PRIMARY` (Terraform output `aurora_dsql_endpoint`)

## 4) Run E2E

On EC2:

```bash
cd /tmp/api-performance-multi-lang/terraform/confluent-option-a
chmod +x run-e2e.sh
./run-e2e.sh
```

If it fails at the bootstrap reachability check, you likely need:
- Confluent Cloud **IPv4** egress (NAT) OR
- Confluent Cloud **PrivateLink** into your VPC


