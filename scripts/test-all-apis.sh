#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Testing All Non-Lambda APIs"
echo "=========================================="

# Start PostgreSQL
echo "Starting PostgreSQL..."
docker-compose up -d postgres-large
sleep 10

# Wait for PostgreSQL to be healthy
echo "Waiting for PostgreSQL to be healthy..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker-compose ps postgres-large | grep -q "healthy"; then
        echo "PostgreSQL is healthy!"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Start all APIs
echo "Building and starting all APIs..."
docker-compose --profile producer-java-rest --profile producer-java-grpc --profile producer-rust-rest --profile producer-rust-grpc --profile producer-go-rest --profile producer-go-grpc up -d --build

# Wait for APIs to be ready
echo "Waiting for APIs to start..."
sleep 30

# Test each API with 10 events
APIS=(
    "java-rest:producer-api-java-rest:9081:rest"
    "java-grpc:producer-api-java-grpc:9090:grpc"
    "rust-rest:producer-api-rust-rest:9082:rest"
    "rust-grpc:producer-api-rust-grpc:9091:grpc"
    "go-rest:producer-api-go-rest:9083:rest"
    "go-grpc:producer-api-go-grpc:9092:grpc"
)

for api_info in "${APIS[@]}"; do
    IFS=':' read -r name container port protocol <<< "$api_info"
    echo ""
    echo "=========================================="
    echo "Testing $name API ($protocol on port $port)"
    echo "=========================================="
    
    # Check if container is running
    if ! docker ps | grep -q "$container"; then
        echo "ERROR: Container $container is not running!"
        docker logs "$container" --tail 50
        continue
    fi
    
    # Run k6 test
    if [ "$protocol" == "rest" ]; then
        docker-compose run --rm -e HOST="$container" -e PORT="$port" -e EVENTS_PER_TYPE=10 k6-throughput k6 run /k6/scripts/send-batch-events.js
    else
        docker-compose run --rm -e HOST="$container" -e PORT="$port" -e PROTO_FILE="/k6/proto/${name%-*}-grpc/event_service.proto" -e EVENTS_PER_TYPE=10 k6-throughput k6 run /k6/scripts/grpc-api-test.js
    fi
    
    echo "Completed test for $name"
    sleep 5
done

echo ""
echo "=========================================="
echo "All tests completed!"
echo "=========================================="
