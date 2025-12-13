#!/bin/bash
# Script to get Aurora DSQL cluster information for Terraform deployment

set -e

echo "=== Aurora DSQL Cluster Information ==="
echo ""
echo "This script helps you find your DSQL cluster information."
echo ""

# Try to list DSQL clusters
echo "Checking for Aurora DSQL clusters..."
DSQL_CLUSTERS=$(aws rds describe-db-clusters --query 'DBClusters[?contains(Engine, `dsql`) || contains(Engine, `DSQL`)]' --output json 2>/dev/null || echo "[]")

if [ "$DSQL_CLUSTERS" != "[]" ] && [ -n "$DSQL_CLUSTERS" ]; then
    echo "Found DSQL clusters:"
    echo "$DSQL_CLUSTERS" | jq -r '.[] | "Cluster: \(.DBClusterIdentifier)\n  Endpoint: \(.Endpoint)\n  Resource ID: \(.DbClusterResourceId)\n  Engine: \(.Engine)\n"'
    echo ""
    echo "To get IAM database users, connect to the cluster and run:"
    echo "  SELECT usename FROM pg_user WHERE usesysid > 16384;"
else
    echo "No DSQL clusters found in this region."
    echo ""
    echo "To find your DSQL cluster information manually:"
    echo "1. Go to AWS Console -> RDS -> Databases"
    echo "2. Find your DSQL cluster"
    echo "3. Note the following:"
    echo "   - Cluster endpoint (e.g., your-cluster.cluster-xxxxx.region.rds.amazonaws.com)"
    echo "   - Cluster resource ID (found in cluster details, format: cluster-xxxxx)"
    echo "   - IAM database user (created in the cluster)"
    echo ""
    echo "Or use AWS CLI:"
    echo "  aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,Endpoint,DbClusterResourceId,Engine]' --output table"
fi

echo ""
echo "=== Required Terraform Variables ==="
echo ""
echo "Add these to terraform.tfvars:"
echo ""
echo "enable_python_lambda_dsql = true"
echo "enable_aurora_dsql = true"
echo "aurora_dsql_endpoint = \"YOUR-CLUSTER-ENDPOINT\""
echo "aurora_dsql_port = 5432"
echo "iam_database_user = \"YOUR-IAM-DB-USER\""
echo "aurora_dsql_cluster_resource_id = \"YOUR-CLUSTER-RESOURCE-ID\""
echo ""

