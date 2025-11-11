#!/bin/bash

# Producer API Results Comparison Script
# Parses JMeter JTL results and generates side-by-side performance comparison reports

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true
source "$SCRIPT_DIR/common-functions.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_BASE_DIR="$BASE_DIR/results/comparison"

# API names
APIS=("producer-api-java-rest" "producer-api-java-grpc" "producer-api-rust-rest" "producer-api-rust-grpc")

# Function to get latest JTL file for an API
get_latest_jtl_file() {
    local test_type=$1
    local api_name=$2
    local api_dir="$RESULTS_BASE_DIR/$test_type/$api_name"
    
    if [ ! -d "$api_dir" ]; then
        echo ""
        return 1
    fi
    
    # Find latest JTL file
    local latest_file=$(ls -t "$api_dir"/*.jtl 2>/dev/null | head -1)
    echo "$latest_file"
}

# Function to generate comparison report
generate_comparison_report() {
    local test_type=$1
    
    print_status "Generating comparison report for test type: $test_type"
    
    local report_file="$RESULTS_BASE_DIR/$test_type/comparison-report.md"
    local csv_file="$RESULTS_BASE_DIR/$test_type/comparison-report.csv"
    local json_file="$RESULTS_BASE_DIR/$test_type/comparison-report.json"
    
    # Initialize report
    cat > "$report_file" << EOF
# Producer API Performance Comparison Report

**Test Type:** $test_type  
**Generated:** $(date)  
**Timestamp:** $(date +%Y%m%d_%H%M%S)

## Overview

This report compares the performance of 4 producer API implementations:
- **producer-api-java-rest**: Spring Boot REST (Port 8081)
- **producer-api-java-grpc**: Spring Boot gRPC (Port 9090)
- **producer-api-rust-rest**: Rust REST (Port 8082)
- **producer-api-rust-grpc**: Rust gRPC (Port 9091)

## Performance Metrics

| API | Total Requests | Success | Failed | Success Rate | Avg Response Time (ms) | Min (ms) | Max (ms) | P90 (ms) | P95 (ms) | P99 (ms) | Throughput (req/s) |
|-----|---------------|---------|--------|--------------|------------------------|----------|----------|----------|----------|----------|-------------------|
EOF

    # Initialize CSV
    echo "API,Total Requests,Success,Failed,Success Rate (%),Avg Response Time (ms),Min (ms),Max (ms),P90 (ms),P95 (ms),P99 (ms),Throughput (req/s),Total Bytes,Sent Bytes" > "$csv_file"
    
    # Initialize JSON
    echo "{" > "$json_file"
    echo "  \"test_type\": \"$test_type\"," >> "$json_file"
    echo "  \"generated\": \"$(date -Iseconds)\"," >> "$json_file"
    echo "  \"apis\": [" >> "$json_file"
    
    local first=true
    local all_metrics=()
    
    # Process each API
    for api_name in "${APIS[@]}"; do
        local jtl_file=$(get_latest_jtl_file "$test_type" "$api_name")
        
        if [ -z "$jtl_file" ] || [ ! -f "$jtl_file" ]; then
            print_error "No JTL file found for $api_name"
            # Add empty row
            echo "| $api_name | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |" >> "$report_file"
            echo "$api_name,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A" >> "$csv_file"
            continue
        fi
        
        print_status "Processing $api_name: $jtl_file"
        
        # Parse metrics
        local metrics=$(parse_jtl_file "$jtl_file")
        
        if [ $? -ne 0 ] || [ -z "$metrics" ]; then
            print_error "Failed to parse metrics for $api_name"
            continue
        fi
        
        # Extract individual metrics
        local total=$(echo "$metrics" | grep "^total:" | cut -d: -f2)
        local success=$(echo "$metrics" | grep "^success:" | cut -d: -f2)
        local failed=$(echo "$metrics" | grep "^failed:" | cut -d: -f2)
        local success_rate=$(echo "$metrics" | grep "^success_rate:" | cut -d: -f2)
        local error_rate=$(echo "$metrics" | grep "^error_rate:" | cut -d: -f2)
        local avg_time=$(echo "$metrics" | grep "^avg_time:" | cut -d: -f2)
        local min_time=$(echo "$metrics" | grep "^min_time:" | cut -d: -f2)
        local max_time=$(echo "$metrics" | grep "^max_time:" | cut -d: -f2)
        local p90=$(echo "$metrics" | grep "^p90:" | cut -d: -f2)
        local p95=$(echo "$metrics" | grep "^p95:" | cut -d: -f2)
        local p99=$(echo "$metrics" | grep "^p99:" | cut -d: -f2)
        local throughput=$(echo "$metrics" | grep "^throughput:" | cut -d: -f2)
        local total_bytes=$(echo "$metrics" | grep "^total_bytes:" | cut -d: -f2)
        local sent_bytes=$(echo "$metrics" | grep "^total_sent_bytes:" | cut -d: -f2)
        
        # Add to markdown report
        printf "| %s | %s | %s | %s | %.2f%% | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |\n" \
            "$api_name" "$total" "$success" "$failed" "$success_rate" "$avg_time" \
            "$min_time" "$max_time" "$p90" "$p95" "$p99" "$throughput" >> "$report_file"
        
        # Add to CSV
        echo "$api_name,$total,$success,$failed,$success_rate,$avg_time,$min_time,$max_time,$p90,$p95,$p99,$throughput,$total_bytes,$sent_bytes" >> "$csv_file"
        
        # Add to JSON
        if [ "$first" = false ]; then
            echo "," >> "$json_file"
        fi
        first=false
        
        cat >> "$json_file" << EOF
    {
      "api": "$api_name",
      "total_requests": $total,
      "success": $success,
      "failed": $failed,
      "success_rate": $success_rate,
      "error_rate": $error_rate,
      "avg_response_time_ms": $avg_time,
      "min_response_time_ms": $min_time,
      "max_response_time_ms": $max_time,
      "p90_ms": $p90,
      "p95_ms": $p95,
      "p99_ms": $p99,
      "throughput_req_per_sec": $throughput,
      "total_bytes": $total_bytes,
      "sent_bytes": $sent_bytes
    }
EOF
        
        # Store metrics for summary
        all_metrics+=("$api_name:$avg_time:$throughput:$success_rate")
    done
    
    # Close JSON
    echo "  ]" >> "$json_file"
    echo "}" >> "$json_file"
    
    # Add summary section to markdown
    cat >> "$report_file" << EOF

## Summary

### Best Performance by Metric

EOF
    
    # Find best performers
    local best_avg_time=""
    local best_throughput=""
    local best_success_rate=""
    local min_avg=999999
    local max_throughput=0
    local max_success=0
    
    for metric in "${all_metrics[@]}"; do
        IFS=':' read -r api avg thr success <<< "$metric"
        if (( $(echo "$avg < $min_avg" | bc -l) )); then
            min_avg=$avg
            best_avg_time=$api
        fi
        if (( $(echo "$thr > $max_throughput" | bc -l) )); then
            max_throughput=$thr
            best_throughput=$api
        fi
        if (( $(echo "$success > $max_success" | bc -l) )); then
            max_success=$success
            best_success_rate=$api
        fi
    done
    
    cat >> "$report_file" << EOF
- **Lowest Average Response Time**: $best_avg_time (${min_avg}ms)
- **Highest Throughput**: $best_throughput (${max_throughput} req/s)
- **Highest Success Rate**: $best_success_rate (${max_success}%)

## Files

- **Markdown Report**: \`comparison-report.md\`
- **CSV Export**: \`comparison-report.csv\`
- **JSON Export**: \`comparison-report.json\`

## Notes

- All tests were run with identical configurations for fair comparison
- Response times are in milliseconds
- Throughput is calculated as requests per second
- Percentiles (P90, P95, P99) represent response time thresholds
EOF
    
    print_success "Comparison report generated: $report_file"
    print_status "CSV export: $csv_file"
    print_status "JSON export: $json_file"
}

# Main function
main() {
    local test_type=$1
    
    if [ -z "$test_type" ]; then
        print_error "Test type is required"
        echo "Usage: $0 <test_type>"
        echo "Test types: smoke, light, spike, heavy"
        exit 1
    fi
    
    # Validate test type
    case "$test_type" in
        smoke|light|spike|heavy)
            ;;
        *)
            print_error "Invalid test type: $test_type"
            echo "Valid test types: smoke, light, spike, heavy"
            exit 1
            ;;
    esac
    
    # Check if results directory exists
    if [ ! -d "$RESULTS_BASE_DIR/$test_type" ]; then
        print_error "Results directory not found: $RESULTS_BASE_DIR/$test_type"
        echo "Please run comparison tests first:"
        echo "  ./run-producer-comparison-tests.sh $test_type"
        exit 1
    fi
    
    generate_comparison_report "$test_type"
    
    print_success "Comparison complete!"
}

# Run main function
main "$@"

