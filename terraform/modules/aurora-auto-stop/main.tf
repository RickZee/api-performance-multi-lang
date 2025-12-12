# Aurora Auto-Stop Lambda Module
# Monitors API Gateway invocations and stops Aurora if no activity for 3 hours

# IAM role for Lambda execution
resource "aws_iam_role" "aurora_auto_stop" {
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
resource "aws_iam_role_policy" "aurora_auto_stop_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.aurora_auto_stop.id

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
resource "aws_iam_role_policy" "aurora_auto_stop_rds" {
  name = "${var.function_name}-rds-policy"
  role = aws_iam_role.aurora_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:StopDBCluster",
          "rds:StartDBCluster"
        ]
        Resource = var.aurora_cluster_arn
      }
    ]
  })
}

# IAM policy for CloudWatch metrics
resource "aws_iam_role_policy" "aurora_auto_stop_cloudwatch" {
  name = "${var.function_name}-cloudwatch-policy"
  role = aws_iam_role.aurora_auto_stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "aurora_auto_stop" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# Lambda function code (inline)
data "archive_file" "aurora_auto_stop_zip" {
  type        = "zip"
  output_path = "${path.module}/aurora_auto_stop.zip"
  source {
    content = <<-EOF
import boto3
import os
from datetime import datetime, timedelta
import json

def handler(event, context):
    """
    Check API Gateway invocations and stop Aurora if no activity for specified hours
    """
    cluster_id = os.environ['AURORA_CLUSTER_ID']
    region = os.environ['AWS_REGION']
    api_gateway_id = os.environ.get('API_GATEWAY_ID', '')
    inactivity_hours = int(os.environ.get('INACTIVITY_HOURS', '3'))
    
    rds = boto3.client('rds', region_name=region)
    cloudwatch = boto3.client('cloudwatch', region_name=region)
    
    # Check current cluster status
    try:
        cluster = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster_status = cluster['DBClusters'][0]['Status']
        
        if cluster_status == 'stopped':
            print(f"Cluster {cluster_id} is already stopped")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Cluster already stopped', 'status': cluster_status})
            }
    except Exception as e:
        print(f"Error checking cluster status: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to check cluster status: {str(e)}'})
        }
    
    # Check API Gateway invocations in the last N hours
    if api_gateway_id:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=inactivity_hours)
        
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/ApiGateway',
                MetricName='Count',
                Dimensions=[
                    {'Name': 'ApiId', 'Value': api_gateway_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,  # 1 hour periods
                Statistics=['Sum']
            )
            
            # Check if there were any invocations
            total_invocations = sum([point['Sum'] for point in response['Datapoints']])
            
            print(f"API Gateway {api_gateway_id} had {total_invocations} invocations in the last {inactivity_hours} hours")
            
            if total_invocations > 0:
                print(f"Activity detected, keeping cluster running")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Activity detected, cluster kept running',
                        'invocations': total_invocations
                    })
                }
        except Exception as e:
            print(f"Warning: Could not check API Gateway metrics: {str(e)}")
            # If we can't check metrics, don't stop the cluster (fail-safe)
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Could not check metrics, keeping cluster running', 'error': str(e)})
            }
    
    # No activity detected, stop the cluster
    try:
        print(f"No activity detected for {inactivity_hours} hours, stopping cluster {cluster_id}")
        rds.stop_db_cluster(DBClusterIdentifier=cluster_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cluster stopped due to {inactivity_hours} hours of inactivity',
                'cluster_id': cluster_id
            })
        }
    except Exception as e:
        error_msg = str(e)
        if 'InvalidDBClusterStateFault' in error_msg and 'stopped' in error_msg.lower():
            print(f"Cluster is already stopped or stopping")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Cluster already stopped or stopping'})
            }
        print(f"Error stopping cluster: {error_msg}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to stop cluster: {error_msg}'})
        }
EOF
    filename = "index.py"
  }
}

# Lambda function (inline Python code)
resource "aws_lambda_function" "aurora_auto_stop" {
  function_name = var.function_name
  role          = aws_iam_role.aurora_auto_stop.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.aurora_auto_stop_zip.output_path
  source_code_hash = data.archive_file.aurora_auto_stop_zip.output_base64sha256

  environment {
    variables = {
      AURORA_CLUSTER_ID = var.aurora_cluster_id
      # AWS_REGION is automatically provided by Lambda runtime, no need to set it
      API_GATEWAY_ID    = var.api_gateway_id
      INACTIVITY_HOURS  = var.inactivity_hours
    }
  }

  depends_on = [
    aws_iam_role_policy.aurora_auto_stop_logs,
    aws_cloudwatch_log_group.aurora_auto_stop
  ]

  tags = var.tags
}

# EventBridge rule to trigger Lambda every hour
resource "aws_cloudwatch_event_rule" "aurora_auto_stop_schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger Aurora auto-stop check every hour"
  schedule_expression = "rate(1 hour)"

  tags = var.tags
}

# EventBridge target
resource "aws_cloudwatch_event_target" "aurora_auto_stop_target" {
  rule      = aws_cloudwatch_event_rule.aurora_auto_stop_schedule.name
  target_id = "${var.function_name}-target"
  arn       = aws_lambda_function.aurora_auto_stop.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "aurora_auto_stop_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aurora_auto_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aurora_auto_stop_schedule.arn
}

