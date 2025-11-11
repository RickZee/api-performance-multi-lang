#!/bin/bash

# Throughput Results Analysis Script
# Analyzes JMeter results to identify max throughput, optimal parallelism, and breaking points

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/color-output.sh" 2>/dev/null || true

# Configuration
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_BASE_DIR="$BASE_DIR/results/throughput"
ANALYSIS_OUTPUT_DIR="$RESULTS_BASE_DIR/analysis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# API list
APIS="producer-api-java-rest producer-api-java-grpc producer-api-rust-rest producer-api-rust-grpc"

# Function to extract metrics from JTL file
extract_metrics() {
    local jtl_file=$1
    local api_name=$2
    
    if [ ! -f "$jtl_file" ]; then
        print_error "JTL file not found: $jtl_file"
        return 1
    fi
    
    print_status "Analyzing $api_name results from $jtl_file..."
    
    # Extract summary statistics using awk
    # JTL format: timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Latency,IdleTime,Connect
    
    # Calculate throughput, response times, error rates per phase
    # Phase identification based on thread group names in labels
    
    local analysis_file="$ANALYSIS_OUTPUT_DIR/${api_name}-analysis-${TIMESTAMP}.txt"
    mkdir -p "$ANALYSIS_OUTPUT_DIR"
    
    {
        echo "=========================================="
        echo "Throughput Analysis: $api_name"
        echo "=========================================="
        echo ""
        echo "File: $jtl_file"
        echo "Analysis Date: $(date)"
        echo ""
        
        # Overall statistics
        echo "--- Overall Statistics ---"
        local total_samples=$(awk -F',' 'NR>1 {count++} END {print count}' "$jtl_file")
        local success_samples=$(awk -F',' 'NR>1 && $8=="true" {count++} END {print count}' "$jtl_file")
        local error_samples=$(awk -F',' 'NR>1 && $8=="false" {count++} END {print count}' "$jtl_file")
        local error_rate=$(awk -v total="$total_samples" -v errors="$error_samples" 'BEGIN {if (total > 0) printf "%.2f", (errors/total)*100; else printf "0.00"}' 2>/dev/null || echo "0.00")
        
        echo "Total Samples: $total_samples"
        echo "Successful: $success_samples"
        echo "Errors: $error_samples"
        echo "Error Rate: ${error_rate}%"
        echo ""
        
        # Calculate throughput (samples per second)
        local first_timestamp=$(awk -F',' 'NR==2 {print $1; exit}' "$jtl_file")
        local last_timestamp=$(awk -F',' 'END {print $1}' "$jtl_file")
        local duration_seconds=$(awk -v first="$first_timestamp" -v last="$last_timestamp" 'BEGIN {printf "%.2f", (last - first) / 1000}' 2>/dev/null || echo "0")
        local throughput=$(awk -v total="$total_samples" -v duration="$duration_seconds" 'BEGIN {if (duration > 0) printf "%.2f", total/duration; else printf "0.00"}' 2>/dev/null || echo "0.00")
        
        echo "Test Duration: ${duration_seconds}s"
        echo "Overall Throughput: ${throughput} req/s"
        echo ""
        
        # Response time statistics
        echo "--- Response Time Statistics ---"
        local avg_response=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if (count > 0) printf "%.2f", sum/count; else printf "0.00"}' "$jtl_file")
        local min_response=$(awk -F',' 'NR>1 {if (NR==2 || $2<min) min=$2} END {printf "%.2f", min}' "$jtl_file")
        local max_response=$(awk -F',' 'NR>1 {if (NR==2 || $2>max) max=$2} END {printf "%.2f", max}' "$jtl_file")
        
        echo "Average Response Time: ${avg_response}ms"
        echo "Min Response Time: ${min_response}ms"
        echo "Max Response Time: ${max_response}ms"
        echo ""
        
        # Calculate percentiles (simplified - for production use a proper statistical tool)
        echo "--- Percentiles (approximate) ---"
        # Sort response times and calculate percentiles
        local p50=$(awk -F',' 'NR>1 {print $2}' "$jtl_file" | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.50)]}')
        local p95=$(awk -F',' 'NR>1 {print $2}' "$jtl_file" | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.95)]}')
        local p99=$(awk -F',' 'NR>1 {print $2}' "$jtl_file" | sort -n | awk '{all[NR] = $0} END{print all[int(NR*0.99)]}')
        
        echo "P50 (Median): ${p50}ms"
        echo "P95: ${p95}ms"
        echo "P99: ${p99}ms"
        echo ""
        
        # Phase-based analysis (if thread group names are in labels)
        echo "--- Phase Analysis ---"
        echo "Note: Detailed phase analysis requires parsing thread group names from labels"
        echo "For detailed phase-by-phase analysis, use JMeter's HTML report or custom scripts"
        echo ""
        
        # Recommendations
        echo "--- Recommendations ---"
        if (( $(echo "$error_rate > 5" | bc -l 2>/dev/null || echo "0") )); then
            echo "WARNING: Error rate exceeds 5% - system may be at breaking point"
        fi
        
        if (( $(echo "$avg_response > 5000" | bc -l 2>/dev/null || echo "0") )); then
            echo "WARNING: Average response time exceeds 5 seconds - performance degradation detected"
        fi
        
        echo ""
        echo "To identify optimal parallelism:"
        echo "1. Review phase-by-phase throughput in JMeter HTML report"
        echo "2. Find the thread count where throughput peaks"
        echo "3. Identify the point where error rate increases significantly"
        echo "4. Look for response time degradation patterns"
        
    } > "$analysis_file"
    
    cat "$analysis_file"
    print_success "Analysis saved to: $analysis_file"
    echo ""
}

# Function to analyze all API results
analyze_all() {
    print_status "=========================================="
    print_status "Throughput Results Analysis"
    print_status "=========================================="
    echo ""
    
    mkdir -p "$ANALYSIS_OUTPUT_DIR"
    
    local found_results=false
    
    for api_name in $APIS; do
        local api_dir="$RESULTS_BASE_DIR/$api_name"
        if [ ! -d "$api_dir" ]; then
            print_warning "No results directory found for $api_name"
            continue
        fi
        
        # Find the most recent JTL file
        local latest_jtl=$(find "$api_dir" -name "*-throughput-*.jtl" -type f | sort -r | head -1)
        
        if [ -z "$latest_jtl" ]; then
            print_warning "No JTL files found for $api_name"
            continue
        fi
        
        found_results=true
        extract_metrics "$latest_jtl" "$api_name"
    done
    
    if [ "$found_results" = false ]; then
        print_error "No results found. Please run throughput tests first:"
        print_status "  ./run-sequential-throughput-tests.sh full"
        exit 1
    fi
    
    # Generate comparison summary
    local summary_file="$ANALYSIS_OUTPUT_DIR/comparison-summary-${TIMESTAMP}.txt"
    {
        echo "=========================================="
        echo "Throughput Comparison Summary"
        echo "=========================================="
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "For detailed analysis of each API, see individual analysis files in:"
        echo "$ANALYSIS_OUTPUT_DIR"
        echo ""
        echo "To identify max throughput and optimal parallelism:"
        echo "1. Review individual analysis files for each API"
        echo "2. Compare throughput values across different thread counts"
        echo "3. Identify the thread count where throughput peaks for each API"
        echo "4. Note the breaking point (where error rate > 5% or response time degrades)"
        echo ""
    } > "$summary_file"
    
    print_success "Comparison summary saved to: $summary_file"
    echo ""
}

# Function to analyze specific API
analyze_api() {
    local api_name=$1
    local api_dir="$RESULTS_BASE_DIR/$api_name"
    
    if [ ! -d "$api_dir" ]; then
        print_error "No results directory found for $api_name"
        exit 1
    fi
    
    # Find the most recent JTL file
    local latest_jtl=$(find "$api_dir" -name "*-throughput-*.jtl" -type f | sort -r | head -1)
    
    if [ -z "$latest_jtl" ]; then
        print_error "No JTL files found for $api_name"
        exit 1
    fi
    
    extract_metrics "$latest_jtl" "$api_name"
}

# Main function
main() {
    case "${1:-all}" in
        "all")
            analyze_all
            ;;
        "producer-api-java-rest"|"producer-api-java-grpc"|"producer-api-rust-rest"|"producer-api-rust-grpc")
            analyze_api "$1"
            ;;
        "help"|"-h"|"--help")
            echo "Throughput Results Analysis"
            echo "=========================="
            echo
            echo "Usage: $0 [api_name|all|help]"
            echo
            echo "Options:"
            echo "  all                  Analyze results for all APIs (default)"
            echo "  producer-api-java-rest         Analyze Spring Boot REST API results"
            echo "  producer-api-java-grpc    Analyze Java gRPC API results"
            echo "  producer-api-rust-rest    Analyze Rust REST API results"
            echo "  producer-api-rust-grpc  Analyze Rust gRPC API results"
            echo "  help                 Show this help message"
            echo
            echo "Examples:"
            echo "  $0                   # Analyze all results"
            echo "  $0 producer-api-java-rest      # Analyze Spring Boot REST API only"
            echo
            echo "Results are saved to: load-test/results/throughput/analysis/"
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

