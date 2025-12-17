#!/bin/bash

# Sequential Results Comprehensive Comparison Script
# Aggregates all sequential test results and generates comprehensive comparison report with analytics

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true
source "$SCRIPT_DIR/common-functions.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_BASE_DIR="$BASE_DIR/load-test/results/sequential"

# API names and test types
APIS=("producer-api-java-rest" "producer-api-java-grpc" "producer-api-rust-rest" "producer-api-rust-grpc")
TEST_TYPES=("smoke" "light" "spike" "heavy")

# Function to get latest JTL file for an API and test type
get_latest_jtl_file() {
    local api_name=$1
    local test_type=$2
    local api_dir="$RESULTS_BASE_DIR/$api_name/$test_type"
    
    if [ ! -d "$api_dir" ]; then
        echo ""
        return 1
    fi
    
    # Find latest JTL file
    local latest_file=$(ls -t "$api_dir"/*.jtl 2>/dev/null | head -1)
    echo "$latest_file"
}

# Function to calculate statistics
calculate_stats() {
    local values="$1"
    local count=$(echo "$values" | wc -w | tr -d ' ')
    
    if [ "$count" -eq 0 ]; then
        echo "0:0:0"
        return
    fi
    
    # Calculate mean
    local sum=0
    local mean=0
    for val in $values; do
        sum=$(echo "$sum + $val" | bc -l)
    done
    mean=$(echo "scale=2; $sum / $count" | bc -l)
    
    # Calculate median (simplified - middle value)
    local sorted=$(echo "$values" | tr ' ' '\n' | sort -n | tr '\n' ' ')
    local median_idx=$((count / 2 + 1))
    local median=$(echo "$sorted" | cut -d' ' -f$median_idx)
    
    # Calculate standard deviation (simplified)
    local variance=0
    for val in $values; do
        local diff=$(echo "$val - $mean" | bc -l)
        local diff_sq=$(echo "$diff * $diff" | bc -l)
        variance=$(echo "$variance + $diff_sq" | bc -l)
    done
    variance=$(echo "scale=2; $variance / $count" | bc -l)
    local stddev=$(echo "scale=2; sqrt($variance)" | bc -l)
    
    echo "${mean}:${median}:${stddev}"
}

# Function to get metrics summary from CSV file
get_metrics_summary() {
    local metrics_file=$1
    if [ ! -f "$metrics_file" ]; then
        echo ""
        return
    fi
    
    # Use Python script to calculate summary if available
    if command -v python3 >/dev/null 2>&1; then
        local summary=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from generate_charts import calculate_metrics_summary
import json
summary = calculate_metrics_summary('$metrics_file')
if summary:
    print(json.dumps(summary))
" 2>/dev/null)
        if [ -n "$summary" ]; then
            echo "$summary"
            return
        fi
    fi
    
    # Fallback: simple awk calculation
    if [ -f "$metrics_file" ] && [ $(wc -l < "$metrics_file") -gt 1 ]; then
        local avg_cpu=$(awk -F',' 'NR>1 {sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$metrics_file" 2>/dev/null || echo "0")
        local max_cpu=$(awk -F',' 'NR>1 {if($4>max || NR==2) max=$4} END {printf "%.2f", max+0}' "$metrics_file" 2>/dev/null || echo "0")
        local avg_mem=$(awk -F',' 'NR>1 {sum+=$5; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$metrics_file" 2>/dev/null || echo "0")
        local max_mem=$(awk -F',' 'NR>1 {if($5>max || NR==2) max=$5} END {printf "%.2f", max+0}' "$metrics_file" 2>/dev/null || echo "0")
        echo "{\"avg_cpu\":$avg_cpu,\"max_cpu\":$max_cpu,\"avg_memory\":$avg_mem,\"max_memory\":$max_mem}"
    else
        echo ""
    fi
}

# Function to generate comprehensive comparison report
generate_comprehensive_report() {
    print_status "Generating comprehensive comparison report..."
    
    local report_file="$RESULTS_BASE_DIR/comprehensive-comparison-report.md"
    local csv_file="$RESULTS_BASE_DIR/comprehensive-comparison-report.csv"
    local json_file="$RESULTS_BASE_DIR/comprehensive-comparison-report.json"
    local charts_dir="$RESULTS_BASE_DIR/charts"
    
    # Generate charts
    print_status "Generating resource usage charts..."
    mkdir -p "$charts_dir"
    if command -v python3 >/dev/null 2>&1 && python3 -c "import matplotlib" 2>/dev/null; then
        python3 "$SCRIPT_DIR/generate-charts.py" "$RESULTS_BASE_DIR" "$charts_dir" 2>/dev/null || print_warning "Chart generation failed or matplotlib not available"
    else
        print_warning "Python3 or matplotlib not available, skipping chart generation"
    fi
    
    # Generate HTML report
    print_status "Generating HTML report with interactive charts..."
    local html_file="$RESULTS_BASE_DIR/comprehensive-comparison-report.html"
    if command -v python3 >/dev/null 2>&1; then
        python3 "$SCRIPT_DIR/generate-html-report.py" "$report_file" "$RESULTS_BASE_DIR" "$html_file" 2>/dev/null || print_warning "HTML report generation failed"
        if [ -f "$html_file" ]; then
            print_status "HTML report generated: $html_file"
        fi
    else
        print_warning "Python3 not available, skipping HTML report generation"
    fi
    
    # Initialize report
    cat > "$report_file" << EOF
# Producer API Comprehensive Performance Comparison Report

**Generated:** $(date)  
**Timestamp:** $(date +%Y%m%d_%H%M%S)  
**Test Method:** Sequential (one API at a time)  
**Resource Limits:** 2G memory, 2.0 CPU (identical for all APIs)

## Executive Summary

This report compares the performance of 4 producer API implementations across multiple test scenarios:
- **producer-api-java-rest**: Spring Boot REST (Port 8081)
- **producer-api-java-grpc**: Spring Boot gRPC (Port 9090)
- **producer-api-rust-rest**: Rust REST (Port 8082)
- **producer-api-rust-grpc**: Rust gRPC (Port 9091)

All tests were run sequentially to ensure fair comparison without resource competition.

## Test Configuration

| Test Type | Threads | Loops | Ramp-up (s) | Description |
|-----------|---------|-------|-------------|-------------|
| Smoke | 5 | 1 | 10 | Quick validation |
| Light | 10 | 10 | 30 | Normal load |
| Spike | 100 | 5 | 10 | Burst traffic |
| Heavy | 500 | 100 | 180 | Sustained high load |

## Results by Test Type

EOF

    # Initialize CSV
    echo "API,Test Type,Total Requests,Success,Failed,Success Rate (%),Avg Response Time (ms),Min (ms),Max (ms),P90 (ms),P95 (ms),P99 (ms),Throughput (req/s),Total Bytes,Sent Bytes,Avg CPU (%),Max CPU (%),Avg Memory (%),Max Memory (%)" > "$csv_file"
    
    # Initialize JSON
    echo "{" > "$json_file"
    echo "  \"generated\": \"$(date -Iseconds)\"," >> "$json_file"
    echo "  \"test_method\": \"sequential\"," >> "$json_file"
    echo "  \"resource_limits\": {" >> "$json_file"
    echo "    \"memory\": \"2G\"," >> "$json_file"
    echo "    \"cpu\": \"2.0\"" >> "$json_file"
    echo "  }," >> "$json_file"
    echo "  \"results\": {" >> "$json_file"
    
    # Store all metrics for analytics
    declare -a all_avg_times
    declare -a all_throughputs
    declare -a all_success_rates
    
    # Process each test type
    local first_test_type=true
    for test_type in "${TEST_TYPES[@]}"; do
        if [ "$first_test_type" = false ]; then
            echo "," >> "$json_file"
        fi
        first_test_type=false
        
        echo "### $test_type Test Results" >> "$report_file"
        echo "" >> "$report_file"
        echo "#### Performance Metrics" >> "$report_file"
        echo "" >> "$report_file"
        echo "| API | Total Requests | Success | Failed | Success Rate | Avg Response Time (ms) | Min (ms) | Max (ms) | P90 (ms) | P95 (ms) | P99 (ms) | Throughput (req/s) |" >> "$report_file"
        echo "|-----|---------------|---------|--------|--------------|------------------------|----------|----------|----------|----------|----------|-------------------|" >> "$report_file"
        
        echo "    \"$test_type\": {" >> "$json_file"
        echo "      \"apis\": [" >> "$json_file"
        
        local first_api=true
        local apis_with_data=0
        for api_name in "${APIS[@]}"; do
            local jtl_file=$(get_latest_jtl_file "$api_name" "$test_type")
            
            if [ -z "$jtl_file" ] || [ ! -f "$jtl_file" ]; then
                print_error "No JTL file found for $api_name ($test_type)"
                # Show API with placeholder data instead of skipping
                echo "| $api_name | - | - | - | - | - | - | - | - | - | - | - |" >> "$report_file"
                echo "$api_name,$test_type,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-" >> "$csv_file"
                continue
            fi
            
            print_status "Processing $api_name ($test_type): $jtl_file"
            
            # Parse metrics
            local metrics=$(parse_jtl_file "$jtl_file")
            
            if [ $? -ne 0 ] || [ -z "$metrics" ]; then
                print_error "Failed to parse metrics for $api_name ($test_type)"
                # Show API with placeholder data instead of skipping
                echo "| $api_name | - | - | - | - | - | - | - | - | - | - | - |" >> "$report_file"
                echo "$api_name,$test_type,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-,-" >> "$csv_file"
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
            
            # Get resource metrics
            local result_dir=$(dirname "$jtl_file")
            local metrics_file=$(find "$result_dir" -name "*-metrics.csv" | head -1)
            local resource_metrics=""
            local avg_cpu="-"
            local max_cpu="-"
            local avg_memory="-"
            local max_memory="-"
            
            if [ -n "$metrics_file" ] && [ -f "$metrics_file" ] && [ $(wc -l < "$metrics_file") -gt 1 ]; then
                resource_metrics=$(get_metrics_summary "$metrics_file")
                if [ -n "$resource_metrics" ]; then
                    avg_cpu=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['avg_cpu'] if d['avg_cpu'] > 0 else '-')" 2>/dev/null || echo "-")
                    max_cpu=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['max_cpu'] if d['max_cpu'] > 0 else '-')" 2>/dev/null || echo "-")
                    avg_memory=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['avg_memory'] if d['avg_memory'] > 0 else '-')" 2>/dev/null || echo "-")
                    max_memory=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['max_memory'] if d['max_memory'] > 0 else '-')" 2>/dev/null || echo "-")
                fi
            fi
            
            # Add to CSV
            echo "$api_name,$test_type,$total,$success,$failed,$success_rate,$avg_time,$min_time,$max_time,$p90,$p95,$p99,$throughput,$total_bytes,$sent_bytes,$avg_cpu,$max_cpu,$avg_memory,$max_memory" >> "$csv_file"
            
            # Add to JSON
            if [ "$first_api" = false ]; then
                echo "," >> "$json_file"
            fi
            first_api=false
            
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
          "sent_bytes": $sent_bytes,
          "resource_usage": {
            "avg_cpu_percent": "$avg_cpu",
            "max_cpu_percent": "$max_cpu",
            "avg_memory_percent": "$avg_memory",
            "max_memory_percent": "$max_memory"
          }
        }
EOF
            
            # Store for analytics
            all_avg_times+=("$avg_time")
            all_throughputs+=("$throughput")
            all_success_rates+=("$success_rate")
        done
        
        echo "      ]" >> "$json_file"
        echo "    }" >> "$json_file"
        
        # Add resource usage section
        echo "" >> "$report_file"
        echo "#### Resource Usage Metrics" >> "$report_file"
        echo "" >> "$report_file"
        echo "| API | Avg CPU % | Max CPU % | Avg Memory % | Max Memory % |" >> "$report_file"
        echo "|-----|-----------|-----------|--------------|--------------|" >> "$report_file"
        
        for api_name in "${APIS[@]}"; do
            local jtl_file=$(get_latest_jtl_file "$api_name" "$test_type")
            if [ -z "$jtl_file" ] || [ ! -f "$jtl_file" ]; then
                # Show API with placeholder data instead of skipping
                echo "| $api_name | - | - | - | - |" >> "$report_file"
                continue
            fi
            
            local result_dir=$(dirname "$jtl_file")
            local metrics_file=$(find "$result_dir" -name "*-metrics.csv" | head -1)
            local avg_cpu="-"
            local max_cpu="-"
            local avg_memory="-"
            local max_memory="-"
            
            if [ -n "$metrics_file" ] && [ -f "$metrics_file" ] && [ $(wc -l < "$metrics_file") -gt 1 ]; then
                local resource_metrics=$(get_metrics_summary "$metrics_file")
                if [ -n "$resource_metrics" ]; then
                    avg_cpu=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['avg_cpu'] if d['avg_cpu'] > 0 else '-')" 2>/dev/null || echo "-")
                    max_cpu=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['max_cpu'] if d['max_cpu'] > 0 else '-')" 2>/dev/null || echo "-")
                    avg_memory=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['avg_memory'] if d['avg_memory'] > 0 else '-')" 2>/dev/null || echo "-")
                    max_memory=$(echo "$resource_metrics" | python3 -c "import sys, json; d=json.load(sys.stdin); print('%.2f' % d['max_memory'] if d['max_memory'] > 0 else '-')" 2>/dev/null || echo "-")
                fi
            fi
            
            echo "| $api_name | $avg_cpu | $max_cpu | $avg_memory | $max_memory |" >> "$report_file"
        done
        
        # Add charts section if available
        echo "" >> "$report_file"
        echo "#### Resource Usage Charts" >> "$report_file"
        echo "" >> "$report_file"
        for api_name in "${APIS[@]}"; do
            local chart_file=$(find "$charts_dir" -name "*${api_name}*${test_type}*chart.png" | head -1)
            if [ -n "$chart_file" ] && [ -f "$chart_file" ]; then
                local chart_name=$(basename "$chart_file")
                echo "**$api_name** Resource Usage:" >> "$report_file"
                echo "" >> "$report_file"
                echo "![$api_name $test_type Resource Usage](charts/$chart_name)" >> "$report_file"
                echo "" >> "$report_file"
            fi
        done
        
        echo "" >> "$report_file"
    done
    
    # Close JSON
    echo "  }" >> "$json_file"
    echo "}" >> "$json_file"
    
    # Add analytics section
    cat >> "$report_file" << EOF

## Performance Analytics

### Overall Performance Rankings

EOF
    
    # Calculate rankings for each metric across all test types
    # This is a simplified version - in a real implementation, you'd aggregate across all test types
    
    cat >> "$report_file" << EOF

### Performance Trends Across Test Types

*Note: Detailed trend analysis requires data from all test types. Review individual test type tables above.*

### Key Insights

1. **Response Time Analysis**: Compare average response times across APIs and test types
2. **Throughput Analysis**: Identify which API handles the most requests per second
3. **Reliability Analysis**: Compare success rates across different load levels
4. **Scalability Analysis**: Observe how each API performs as load increases

### Recommendations

Based on the test results:
- **Best Overall Performance**: Review metrics across all test types
- **Best for Low Load**: Check smoke and light test results
- **Best for High Load**: Check spike and heavy test results
- **Most Reliable**: Compare success rates across all scenarios

## Files

- **Markdown Report**: \`comprehensive-comparison-report.md\`
- **CSV Export**: \`comprehensive-comparison-report.csv\`
- **JSON Export**: \`comprehensive-comparison-report.json\`

## Notes

- All tests were run sequentially (one API at a time) for fair comparison
- Resource limits were identical for all APIs (2G memory, 2.0 CPU)
- Response times are in milliseconds
- Throughput is calculated as requests per second
- Percentiles (P90, P95, P99) represent response time thresholds
EOF
    
    print_success "Comprehensive comparison report generated: $report_file"
    print_status "CSV export: $csv_file"
    print_status "JSON export: $json_file"
}

# Main function
main() {
    # Check if results directory exists
    if [ ! -d "$RESULTS_BASE_DIR" ]; then
        print_error "Results directory not found: $RESULTS_BASE_DIR"
        echo "Please run sequential tests first:"
        echo "  ./run-sequential-comparison-tests.sh"
        exit 1
    fi
    
    # Check if we have any results
    local result_count=$(find "$RESULTS_BASE_DIR" -name "*.jtl" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$result_count" -eq 0 ]; then
        print_error "No test results found in $RESULTS_BASE_DIR"
        echo "Please run sequential tests first:"
        echo "  ./run-sequential-comparison-tests.sh"
        exit 1
    fi
    
    print_status "Found $result_count result files"
    generate_comprehensive_report
    
    print_success "Comprehensive comparison complete!"
    print_status "View report: $RESULTS_BASE_DIR/comprehensive-comparison-report.md"
}

# Run main function
main "$@"
