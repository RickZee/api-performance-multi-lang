# DSQL Auto-Resume Lambda Module
# Ensures DSQL cluster is available when API requests arrive

# IAM role for Lambda execution
resource "aws_iam_role" "dsql_auto_resume" {
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
resource "aws_iam_role_policy" "dsql_auto_resume_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.dsql_auto_resume.id

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

# IAM policy for DSQL operations
resource "aws_iam_role_policy" "dsql_auto_resume_dsql" {
  name = "${var.function_name}-dsql-policy"
  role = aws_iam_role.dsql_auto_resume.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DescribeCluster",
          "dsql:ModifyCluster"
        ]
        Resource = var.dsql_cluster_arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "dsql_auto_resume" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda function code (inline)
data "archive_file" "dsql_auto_resume_zip" {
  type        = "zip"
  output_path = "${path.module}/dsql_auto_resume.zip"
  source {
    content  = <<-EOF
import boto3
import os
import json

def handler(event, context):
    """
    Ensure DSQL cluster is available (scale up if paused or at minimum capacity).
    Called by API Lambda when database connection fails or is slow.
    """
    cluster_resource_id = os.environ['DSQL_CLUSTER_RESOURCE_ID']
    region = os.environ.get('AWS_REGION') or context.invoked_function_arn.split(':')[3]
    target_min_capacity = float(os.environ.get('DSQL_TARGET_MIN_CAPACITY', '1'))
    
    dsql = boto3.client('dsql', region_name=region)
    
    try:
        # Check current cluster status
        cluster = dsql.describe_cluster(ClusterResourceId=cluster_resource_id)
        cluster_status = cluster.get('Status', 'unknown')
        scaling_config = cluster.get('ScalingConfiguration', {})
        current_min_capacity = scaling_config.get('MinCapacity', 1)
        current_max_capacity = scaling_config.get('MaxCapacity', 2)
        
        print(f"Cluster {cluster_resource_id} current status: {cluster_status}, min capacity: {current_min_capacity} ACU")
        
        # If already at target capacity or higher, return success
        if current_min_capacity >= target_min_capacity:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Cluster is available (min capacity: {current_min_capacity} ACU)',
                    'status': cluster_status,
                    'min_capacity': current_min_capacity,
                    'cluster_resource_id': cluster_resource_id
                })
            }
        
        # If at minimum capacity or paused, scale up to target
        if current_min_capacity < target_min_capacity:
            print(f"Scaling up cluster {cluster_resource_id} from {current_min_capacity} ACU to {target_min_capacity} ACU")
            dsql.modify_cluster(
                ClusterResourceId=cluster_resource_id,
                ScalingConfiguration={
                    'MinCapacity': target_min_capacity,
                    'MaxCapacity': current_max_capacity
                }
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cluster scale-up initiated',
                    'status': 'scaling',
                    'cluster_resource_id': cluster_resource_id,
                    'note': 'Database is scaling up. Please retry your request in 30-60 seconds.'
                })
            }
        
        # If in another state, return info
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cluster is in state: {cluster_status}',
                'status': cluster_status,
                'cluster_resource_id': cluster_resource_id
            })
        }
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error managing cluster: {error_msg}")
        
        # Check if it's a state error (already scaling)
        if 'InvalidClusterStateFault' in error_msg or 'InvalidState' in error_msg:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cluster is in transition state',
                    'status': 'transitioning',
                    'cluster_resource_id': cluster_resource_id
                })
            }
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to manage cluster: {error_msg}',
                'cluster_resource_id': cluster_resource_id
            })
        }
EOF
    filename = "index.py"
  }
}

# Lambda function (inline Python code)
resource "aws_lambda_function" "dsql_auto_resume" {
  function_name = var.function_name
  role          = aws_iam_role.dsql_auto_resume.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.dsql_auto_resume_zip.output_path
  source_code_hash = data.archive_file.dsql_auto_resume_zip.output_base64sha256

  environment {
    variables = {
      DSQL_CLUSTER_RESOURCE_ID = var.dsql_cluster_resource_id
      # AWS_REGION is automatically provided by Lambda runtime
      DSQL_TARGET_MIN_CAPACITY = tostring(var.dsql_target_min_capacity)
    }
  }

  depends_on = [
    aws_iam_role_policy.dsql_auto_resume_logs,
    aws_cloudwatch_log_group.dsql_auto_resume
  ]

  tags = var.tags
}
