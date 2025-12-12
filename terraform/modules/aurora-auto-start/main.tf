# Aurora Auto-Start Lambda Module
# Starts Aurora cluster when invoked (typically by API Lambda on connection failure)

# IAM role for Lambda execution
resource "aws_iam_role" "aurora_auto_start" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for CloudWatch Logs
resource "aws_iam_role_policy" "aurora_auto_start_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.aurora_auto_start.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM policy for RDS operations
resource "aws_iam_role_policy" "aurora_auto_start_rds" {
  name = "${var.function_name}-rds-policy"
  role = aws_iam_role.aurora_auto_start.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:StartDBCluster"
        ]
        Resource = var.aurora_cluster_arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "aurora_auto_start" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda function code (inline)
data "archive_file" "aurora_auto_start_zip" {
  type        = "zip"
  output_path = "${path.module}/aurora_auto_start.zip"
  source {
    content = <<-EOF
import boto3
import os
import json

def handler(event, context):
    """
    Start Aurora cluster if it is stopped.
    Called by API Lambda when database connection fails.
    """
    cluster_id = os.environ['AURORA_CLUSTER_ID']
    region = os.environ['AWS_REGION']
    
    rds = boto3.client('rds', region_name=region)
    
    try:
        # Check current cluster status
        cluster = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster_status = cluster['DBClusters'][0]['Status']
        
        print(f"Cluster {cluster_id} current status: {cluster_status}")
        
        # If already available or starting, return success
        if cluster_status in ['available', 'starting']:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Cluster is {cluster_status}',
                    'status': cluster_status,
                    'cluster_id': cluster_id
                })
            }
        
        # If stopped, start it
        if cluster_status == 'stopped':
            print(f"Starting cluster {cluster_id}")
            rds.start_db_cluster(DBClusterIdentifier=cluster_id)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cluster start initiated',
                    'status': 'starting',
                    'cluster_id': cluster_id,
                    'note': 'Database is starting. Please retry your request in 1-2 minutes.'
                })
            }
        
        # If in another state, return info
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cluster is in state: {cluster_status}',
                'status': cluster_status,
                'cluster_id': cluster_id
            })
        }
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error managing cluster: {error_msg}")
        
        # Check if it's a state error (already starting/stopping)
        if 'InvalidDBClusterStateFault' in error_msg:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cluster is in transition state',
                    'status': 'transitioning',
                    'cluster_id': cluster_id
                })
            }
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to manage cluster: {error_msg}',
                'cluster_id': cluster_id
            })
        }
EOF
    filename = "index.py"
  }
}

# Lambda function (inline Python code)
resource "aws_lambda_function" "aurora_auto_start" {
  function_name = var.function_name
  role          = aws_iam_role.aurora_auto_start.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.aurora_auto_start_zip.output_path
  source_code_hash = data.archive_file.aurora_auto_start_zip.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ID = var.aurora_cluster_id
      # AWS_REGION is automatically provided by Lambda runtime
    }
  }

  depends_on = [
    aws_iam_role_policy.aurora_auto_start_logs,
    aws_cloudwatch_log_group.aurora_auto_start
  ]

  tags = var.tags
}

