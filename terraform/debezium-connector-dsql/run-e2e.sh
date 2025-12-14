#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

if [ ! -f "$HERE/connect.env" ]; then
  echo "Missing $HERE/connect.env"
  echo "Copy $HERE/connect.env.example -> $HERE/connect.env and fill in values."
  exit 1
fi

set -a
source "$HERE/connect.env"
set +a

require() {
  local v="$1"
  if [ -z "${!v:-}" ]; then
    echo "Missing required env var: $v"
    exit 1
  fi
}

require CC_BOOTSTRAP_SERVERS
require CC_KAFKA_API_KEY
require CC_KAFKA_API_SECRET
require DSQL_ENDPOINT_PRIMARY
require DSQL_IAM_USERNAME
require DSQL_DATABASE_NAME
require DSQL_TABLE

CONNECTOR_NAME="${CONNECTOR_NAME:-dsql-cdc-source-event-headers}"
TOPIC_PREFIX="${TOPIC_PREFIX:-dsql-cdc}"
ROUTED_TOPIC="${ROUTED_TOPIC:-raw-event-headers}"
CONNECT_GROUP_ID="${CONNECT_GROUP_ID:-dsql-connect-ec2}"
CONNECT_CONFIG_STORAGE_TOPIC="${CONNECT_CONFIG_STORAGE_TOPIC:-_dsql_connect_configs}"
CONNECT_OFFSET_STORAGE_TOPIC="${CONNECT_OFFSET_STORAGE_TOPIC:-_dsql_connect_offsets}"
CONNECT_STATUS_STORAGE_TOPIC="${CONNECT_STATUS_STORAGE_TOPIC:-_dsql_connect_status}"

echo "=== Option A E2E: DSQL -> Kafka Connect on EC2 -> Confluent Cloud ==="
echo "Bootstrap:   $CC_BOOTSTRAP_SERVERS"
echo "DSQL:        $DSQL_ENDPOINT_PRIMARY"
echo "DB/Table:    $DSQL_DATABASE_NAME / $DSQL_TABLE"
echo "Topic out:   $ROUTED_TOPIC"
echo ""

echo "== Preflight: DNS + TCP reachability to Confluent bootstrap =="
BOOT_HOST="${CC_BOOTSTRAP_SERVERS%:*}"
BOOT_PORT="${CC_BOOTSTRAP_SERVERS##*:}"
getent ahosts "$BOOT_HOST" | head -n 5 || true
timeout 5 bash -lc "cat < /dev/null > /dev/tcp/$BOOT_HOST/$BOOT_PORT" && echo "✓ TCP ok" || {
  echo "✗ Cannot reach $CC_BOOTSTRAP_SERVERS from this EC2 instance."
  echo "  If you have no IPv4 NAT, Confluent endpoints must be reachable over IPv6 or via PrivateLink."
  exit 1
}
echo ""

echo "== Installing prerequisites (docker + jq + envsubst) =="
if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y docker
  sudo systemctl enable --now docker
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker not running. Try: sudo systemctl start docker"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  sudo dnf install -y jq
fi
if ! command -v envsubst >/dev/null 2>&1; then
  sudo dnf install -y gettext
fi
if ! command -v psql >/dev/null 2>&1; then
  sudo dnf install -y postgresql15
fi
if ! command -v java >/dev/null 2>&1; then
  sudo dnf install -y java-17-amazon-corretto-headless
fi

echo ""
echo "== Building custom connector fat JAR =="
cd "$REPO_ROOT/debezium-connector-dsql"
./gradlew clean jar --no-daemon

JAR_PATH="$REPO_ROOT/debezium-connector-dsql/build/libs/debezium-connector-dsql-1.0.0.jar"
if [ ! -f "$JAR_PATH" ]; then
  echo "Build succeeded but jar not found at: $JAR_PATH"
  exit 1
fi

echo "== Preparing plugin directory for Kafka Connect =="
mkdir -p "$HERE/plugins/debezium-connector-dsql"
cp -f "$JAR_PATH" "$HERE/plugins/debezium-connector-dsql/"

echo ""
echo "== Starting Kafka Connect worker (Docker) =="
cd "$HERE"

# Make sure envs are visible to docker compose
export CONNECTOR_NAME TOPIC_PREFIX ROUTED_TOPIC CONNECT_GROUP_ID CONNECT_CONFIG_STORAGE_TOPIC CONNECT_OFFSET_STORAGE_TOPIC CONNECT_STATUS_STORAGE_TOPIC

docker compose -f docker-compose.connect.yml down --remove-orphans >/dev/null 2>&1 || true
docker compose -f docker-compose.connect.yml up -d

echo "Waiting for Connect REST API..."
for i in {1..60}; do
  if curl -fsS "http://localhost:8083/" >/dev/null 2>&1; then
    echo "✓ Connect REST is up"
    break
  fi
  sleep 2
done

echo ""
echo "== Creating Kafka Connect internal topics + output topic in Confluent Cloud =="
cat > /tmp/cc.properties <<EOF
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${CC_KAFKA_API_KEY}" password="${CC_KAFKA_API_SECRET}";
ssl.endpoint.identification.algorithm=https
EOF

docker run --rm confluentinc/cp-kafka:7.4.0 bash -lc "
cat > /tmp/cc.properties <<'PROPS'
$(cat /tmp/cc.properties)
PROPS

kafka-topics --bootstrap-server '$CC_BOOTSTRAP_SERVERS' --command-config /tmp/cc.properties --create --if-not-exists --topic '$CONNECT_CONFIG_STORAGE_TOPIC' --partitions 1 --replication-factor 3 --config cleanup.policy=compact
kafka-topics --bootstrap-server '$CC_BOOTSTRAP_SERVERS' --command-config /tmp/cc.properties --create --if-not-exists --topic '$CONNECT_OFFSET_STORAGE_TOPIC' --partitions 25 --replication-factor 3 --config cleanup.policy=compact
kafka-topics --bootstrap-server '$CC_BOOTSTRAP_SERVERS' --command-config /tmp/cc.properties --create --if-not-exists --topic '$CONNECT_STATUS_STORAGE_TOPIC' --partitions 5 --replication-factor 3 --config cleanup.policy=compact
kafka-topics --bootstrap-server '$CC_BOOTSTRAP_SERVERS' --command-config /tmp/cc.properties --create --if-not-exists --topic '$ROUTED_TOPIC' --partitions 3 --replication-factor 3
"

echo ""
echo "== Deploying connector to local Kafka Connect =="
envsubst < "$HERE/connector.json.tmpl" > /tmp/dsql-connector.json
curl -fsS -X PUT "http://localhost:8083/connectors/$CONNECTOR_NAME/config" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/dsql-connector.json >/dev/null

echo "Waiting for connector to be RUNNING..."
for i in {1..60}; do
  status="$(curl -fsS "http://localhost:8083/connectors/$CONNECTOR_NAME/status" | jq -r '.connector.state' 2>/dev/null || true)"
  if [ "$status" = "RUNNING" ]; then
    echo "✓ Connector RUNNING"
    break
  fi
  if [ -n "$status" ]; then
    echo "  status=$status"
  fi
  sleep 2
done

echo ""
echo "== Inserting test events into DSQL =="
TOKEN="$(aws rds generate-db-auth-token --hostname "$DSQL_ENDPOINT_PRIMARY" --port 5432 --username "$DSQL_IAM_USERNAME" --region us-east-1)"
PGPASSWORD="$TOKEN" psql -h "$DSQL_ENDPOINT_PRIMARY" -p 5432 -U "$DSQL_IAM_USERNAME" -d "$DSQL_DATABASE_NAME" -f "$REPO_ROOT/terraform/insert-test-events.sql" >/dev/null
echo "✓ Inserted test rows"

echo ""
echo "== Consuming messages from Confluent Cloud topic: $ROUTED_TOPIC =="
docker run --rm confluentinc/cp-kafka:7.4.0 bash -lc "
cat > /tmp/cc.properties <<'PROPS'
$(cat /tmp/cc.properties)
PROPS
kafka-console-consumer --bootstrap-server '$CC_BOOTSTRAP_SERVERS' --consumer.config /tmp/cc.properties --topic '$ROUTED_TOPIC' --from-beginning --max-messages 10 --timeout-ms 30000
"

echo ""
echo "=== SUCCESS: end-to-end flow validated ==="
echo "Connector: $CONNECTOR_NAME"
echo "Topic:     $ROUTED_TOPIC"


