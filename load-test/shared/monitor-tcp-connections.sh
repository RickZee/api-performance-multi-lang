#!/bin/bash
# Monitor TCP connections for k6 and API containers
# Usage: ./monitor-tcp-connections.sh [container_name] [interval_seconds]

set -e

CONTAINER_NAME="${1:-k6-throughput}"
INTERVAL="${2:-5}"

echo "=========================================="
echo "TCP Connection Monitor"
echo "=========================================="
echo "Container: $CONTAINER_NAME"
echo "Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

# Function to get TCP connection stats
get_tcp_stats() {
    local container=$1
    
    # Check if container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "[$(date +%H:%M:%S)] Container '$container' not running"
        return 1
    fi
    
    # Get container PID
    local pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    if [ -z "$pid" ]; then
        echo "[$(date +%H:%M:%S)] Cannot get PID for container '$container'"
        return 1
    fi
    
    # Get TCP connection stats from container's network namespace
    echo "[$(date +%H:%M:%S)] TCP Connections for $container (PID: $pid):"
    
    # Count connections by state
    local established=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c ESTAB || echo "0")
    local time_wait=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c TIME-WAIT || echo "0")
    local close_wait=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c CLOSE-WAIT || echo "0")
    local syn_sent=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c SYN-SENT || echo "0")
    local syn_recv=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c SYN-RECV || echo "0")
    local fin_wait1=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c FIN-WAIT-1 || echo "0")
    local fin_wait2=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c FIN-WAIT-2 || echo "0")
    local total=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | tail -n +2 | wc -l || echo "0")
    
    echo "  ESTABLISHED: $established"
    echo "  TIME-WAIT:   $time_wait"
    echo "  CLOSE-WAIT:  $close_wait"
    echo "  SYN-SENT:    $syn_sent"
    echo "  SYN-RECV:    $syn_recv"
    echo "  FIN-WAIT-1:  $fin_wait1"
    echo "  FIN-WAIT-2:  $fin_wait2"
    echo "  TOTAL:       $total"
    
    # Show connections to gRPC ports (9090, 9092)
    echo ""
    echo "  Connections to gRPC servers:"
    local grpc_conns=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -E ':(9090|9092)' | wc -l || echo "0")
    echo "    Port 9090/9092: $grpc_conns"
    
    # Show connections to REST ports (8081, 9083)
    echo "  Connections to REST servers:"
    local rest_conns=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -E ':(8081|9083)' | wc -l || echo "0")
    echo "    Port 8081/9083: $rest_conns"
    
    # Show ephemeral port usage
    echo ""
    echo "  Ephemeral port usage:"
    local ephemeral_ports=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -oE ':[0-9]{5,}' | grep -vE ':(9090|9092|8081|9083)' | sort -u | wc -l || echo "0")
    echo "    Unique ephemeral ports: $ephemeral_ports"
    
    # Check for connection errors (if available in /proc)
    if [ -d "/proc/$pid/net" ]; then
        local tcp_retrans=$(cat "/proc/$pid/net/snmp" 2>/dev/null | grep "^Tcp:" | awk '{print $13}' || echo "N/A")
        echo "  TCP Retransmissions: $tcp_retrans"
    fi
    
    echo ""
    return 0
}

# Function to monitor API containers
monitor_api_containers() {
    echo "[$(date +%H:%M:%S)] API Container TCP Stats:"
    
    for api in producer-api-java-grpc producer-api-rust-grpc producer-api-go-grpc \
               producer-api-java-rest producer-api-rust-rest producer-api-go-rest; do
        if docker ps --format '{{.Names}}' | grep -q "^${api}$"; then
            local pid=$(docker inspect -f '{{.State.Pid}}' "$api" 2>/dev/null || echo "")
            if [ -n "$pid" ]; then
                local established=$(nsenter -t "$pid" -n ss -tn 2>/dev/null | grep -c ESTAB || echo "0")
                echo "  $api: $established ESTABLISHED connections"
            fi
        fi
    done
    echo ""
}

# Main monitoring loop
while true; do
    get_tcp_stats "$CONTAINER_NAME"
    monitor_api_containers
    echo "----------------------------------------"
    sleep "$INTERVAL"
done
