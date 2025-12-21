#!/bin/bash

# Script to check auto-stop status for Bastion Host, Aurora Cluster, and DSQL Cluster
# Checks Lambda function logs, resource states, and EventBridge rules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_NAME="${PROJECT_NAME:-producer-api}"
AWS_REGION="${AWS_REGION:-us-east-1}"
HOURS_TO_CHECK="${HOURS_TO_CHECK:-24}"

# Function names
BASTION_AUTO_STOP="${PROJECT_NAME}-bastion-auto-stop"
AURORA_AUTO_STOP="${PROJECT_NAME}-aurora-auto-stop"
DSQL_AUTO_PAUSE="${PROJECT_NAME}-dsql-auto-pause"

echo -e "${BLUE}=== Auto-Stop Status Check ===${NC}"
echo "Project: $PROJECT_NAME"
echo "Region: $AWS_REGION"
echo "Checking last $HOURS_TO_CHECK hours"
echo ""

# Function to check Lambda function existence and recent logs
check_lambda_function() {
    local function_name=$1
    local resource_type=$2
    
    echo -e "${BLUE}--- Checking $resource_type Auto-Stop Lambda ---${NC}"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" &>/dev/null; then
        echo -e "${YELLOW}  ⚠ Lambda function '$function_name' not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}  ✓ Lambda function exists: $function_name${NC}"
    
    # Get function configuration
    local config=$(aws lambda get-function-configuration --function-name "$function_name" --region "$AWS_REGION" 2>/dev/null)
    local state=$(echo "$config" | jq -r '.State // "Active"')
    local last_modified=$(echo "$config" | jq -r '.LastModified // "unknown"')
    
    echo "  State: $state"
    echo "  Last Modified: $last_modified"
    
    # Check EventBridge rule
    local rule_name="${function_name}-schedule"
    if aws events describe-rule --name "$rule_name" --region "$AWS_REGION" &>/dev/null; then
        local rule=$(aws events describe-rule --name "$rule_name" --region "$AWS_REGION" 2>/dev/null)
        local rule_state=$(echo "$rule" | jq -r '.State // "ENABLED"')
        local schedule=$(echo "$rule" | jq -r '.ScheduleExpression // "N/A"')
        echo -e "  EventBridge Rule: ${GREEN}$rule_state${NC} (Schedule: $schedule)"
    else
        echo -e "  ${YELLOW}EventBridge rule not found: $rule_name${NC}"
    fi
    
    # Check CloudWatch Logs
    local log_group="/aws/lambda/$function_name"
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$AWS_REGION" --query "logGroups[?logGroupName=='$log_group']" --output text | grep -q "$log_group"; then
        echo "  Log Group: $log_group"
        
        # Get recent log streams (last N hours)
        local start_time=$(($(date +%s) - HOURS_TO_CHECK * 3600))000
        local end_time=$(date +%s)000
        
        local log_events=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --start-time "$start_time" \
            --end-time "$end_time" \
            --region "$AWS_REGION" \
            --max-items 50 \
            2>/dev/null || echo '{"events": []}')
        
        local event_count=$(echo "$log_events" | jq '.events | length')
        echo "  Recent log events (last $HOURS_TO_CHECK hours): $event_count"
        
        if [ "$event_count" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Lambda has been executing${NC}"
            
            # Show last few log messages
            echo "  Last few log messages:"
            echo "$log_events" | jq -r '.events[-5:] | .[] | "    [\(.timestamp/1000 | strftime("%Y-%m-%d %H:%M:%S UTC"))] \(.message)"' | tail -5
            
            # Check for stop/pause actions
            local stop_actions=$(echo "$log_events" | jq -r '.events[].message' | grep -i "stopped\|paused\|scaled down" | wc -l | tr -d ' ')
            if [ "$stop_actions" -gt 0 ]; then
                echo -e "  ${GREEN}  ✓ Found $stop_actions stop/pause action(s)${NC}"
            fi
        else
            echo -e "  ${YELLOW}  ⚠ No log events in the last $HOURS_TO_CHECK hours${NC}"
        fi
    else
        echo -e "  ${YELLOW}  ⚠ Log group not found: $log_group${NC}"
    fi
    
    echo ""
}

# Function to check EC2 instance status
check_bastion_instance() {
    echo -e "${BLUE}--- Checking Bastion Host EC2 Instance ---${NC}"
    
    # Try to find bastion instance by tags
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running,stopped,stopping" \
        --region "$AWS_REGION" \
        --query 'Reservations[*].Instances[*].[InstanceId,State.Name,LaunchTime]' \
        --output json 2>/dev/null || echo '[]')
    
    local instance_count=$(echo "$instances" | jq 'length')
    
    if [ "$instance_count" -eq 0 ]; then
        echo -e "${YELLOW}  ⚠ No bastion instances found${NC}"
    else
        echo "$instances" | jq -r '.[] | "  Instance ID: \(.[0])\n  State: \(.[1])\n  Launch Time: \(.[2])"'
        
        local stopped_count=$(echo "$instances" | jq '[.[] | select(.[1] == "stopped")] | length')
        if [ "$stopped_count" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Found $stopped_count stopped instance(s) - auto-stop may have worked${NC}"
        fi
    fi
    
    echo ""
}

# Function to check Aurora cluster status
check_aurora_cluster() {
    echo -e "${BLUE}--- Checking Aurora PostgreSQL Cluster ---${NC}"
    
    # Try to find cluster by project name
    local clusters=$(aws rds describe-db-clusters \
        --region "$AWS_REGION" \
        --query 'DBClusters[?contains(DBClusterIdentifier, `'"$PROJECT_NAME"'`)].[DBClusterIdentifier,Status]' \
        --output json 2>/dev/null || echo '[]')
    
    local cluster_count=$(echo "$clusters" | jq 'length')
    
    if [ "$cluster_count" -eq 0 ]; then
        echo -e "${YELLOW}  ⚠ No Aurora clusters found with project name${NC}"
    else
        echo "$clusters" | jq -r '.[] | "  Cluster: \(.[0])\n  Status: \(.[1])"'
        
        local stopped_count=$(echo "$clusters" | jq '[.[] | select(.[1] == "stopped")] | length')
        if [ "$stopped_count" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Found $stopped_count stopped cluster(s) - auto-stop may have worked${NC}"
        fi
    fi
    
    echo ""
}

# Function to check DSQL cluster status
check_dsql_cluster() {
    echo -e "${BLUE}--- Checking Aurora DSQL Cluster ---${NC}"
    
    # Try to find DSQL cluster
    local clusters=$(aws dsql list-clusters \
        --region "$AWS_REGION" \
        --query 'Clusters[?contains(ClusterResourceId, `'"$PROJECT_NAME"'`) || contains(ClusterArn, `'"$PROJECT_NAME"'`)].[ClusterResourceId,Status,ScalingConfiguration.MinCapacity]' \
        --output json 2>/dev/null || echo '[]')
    
    local cluster_count=$(echo "$clusters" | jq 'length')
    
    if [ "$cluster_count" -eq 0 ]; then
        echo -e "${YELLOW}  ⚠ No DSQL clusters found with project name${NC}"
        echo "  Note: DSQL clusters may use different naming. Checking all clusters..."
        
        # Try to list all clusters
        local all_clusters=$(aws dsql list-clusters --region "$AWS_REGION" --query 'Clusters[*].[ClusterResourceId,Status,ScalingConfiguration.MinCapacity]' --output json 2>/dev/null || echo '[]')
        local all_count=$(echo "$all_clusters" | jq 'length')
        
        if [ "$all_count" -gt 0 ]; then
            echo "  Found $all_count DSQL cluster(s) in region:"
            echo "$all_clusters" | jq -r '.[] | "    Resource ID: \(.[0])\n    Status: \(.[1])\n    Min Capacity: \(.[2] // "N/A") ACU\n"'
            
            local paused_count=$(echo "$all_clusters" | jq '[.[] | select(.[2] == 0)] | length')
            if [ "$paused_count" -gt 0 ]; then
                echo -e "${GREEN}  ✓ Found $paused_count paused cluster(s) (0 ACU) - auto-pause may have worked${NC}"
            fi
        fi
    else
        echo "$clusters" | jq -r '.[] | "  Resource ID: \(.[0])\n  Status: \(.[1])\n  Min Capacity: \(.[2] // "N/A") ACU"'
        
        local paused_count=$(echo "$clusters" | jq '[.[] | select(.[2] == 0)] | length')
        if [ "$paused_count" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Found $paused_count paused cluster(s) (0 ACU) - auto-pause may have worked${NC}"
        fi
    fi
    
    echo ""
}

# Main execution
echo "Checking AWS resources..."
echo ""

# Check Lambda functions
check_lambda_function "$BASTION_AUTO_STOP" "Bastion Host"
check_lambda_function "$AURORA_AUTO_STOP" "Aurora PostgreSQL"
check_lambda_function "$DSQL_AUTO_PAUSE" "DSQL"

# Check resource states
check_bastion_instance
check_aurora_cluster
check_dsql_cluster

echo -e "${BLUE}=== Summary ===${NC}"
echo "To view detailed logs, use:"
echo "  aws logs tail /aws/lambda/$BASTION_AUTO_STOP --follow --region $AWS_REGION"
echo "  aws logs tail /aws/lambda/$AURORA_AUTO_STOP --follow --region $AWS_REGION"
echo "  aws logs tail /aws/lambda/$DSQL_AUTO_PAUSE --follow --region $AWS_REGION"
