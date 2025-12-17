# DSQL Auto-Pause Lambda Module
# Monitors API Gateway invocations and pauses/scales down DSQL if no activity for specified hours

# IAM role for Lambda execution
resource "aws_iam_role" "dsql_auto_pause" {
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
resource "aws_iam_role_policy" "dsql_auto_pause_logs" {
  name = "${var.function_name}-logs-policy"
  role = aws_iam_role.dsql_auto_pause.id

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
resource "aws_iam_role_policy" "dsql_auto_pause_dsql" {
  name = "${var.function_name}-dsql-policy"
  role = aws_iam_role.dsql_auto_pause.id

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

# IAM policy for CloudWatch metrics
resource "aws_iam_role_policy" "dsql_auto_pause_cloudwatch" {
  name = "${var.function_name}-cloudwatch-policy"
  role = aws_iam_role.dsql_auto_pause.id

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

# IAM policy for SNS notifications
resource "aws_iam_role_policy" "dsql_auto_pause_sns" {
  count = var.admin_email != "" ? 1 : 0
  name  = "${var.function_name}-sns-policy"
  role  = aws_iam_role.dsql_auto_pause.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dsql_auto_pause_notifications[0].arn
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "dsql_auto_pause" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = var.tags
}

# SNS Topic for DSQL auto-pause notifications
resource "aws_sns_topic" "dsql_auto_pause_notifications" {
  count = var.admin_email != "" ? 1 : 0
  name  = "${var.function_name}-notifications"

  tags = merge(
    var.tags,
    {
      Name = "${var.function_name}-notifications"
    }
  )
}

# SNS Email Subscription (requires confirmation)
resource "aws_sns_topic_subscription" "dsql_auto_pause_email" {
  count     = var.admin_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.dsql_auto_pause_notifications[0].arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# Lambda function code (inline)
data "archive_file" "dsql_auto_pause_zip" {
  type        = "zip"
  output_path = "${path.module}/dsql_auto_pause.zip"
  source {
    content  = <<-EOF
import boto3
import os
from datetime import datetime, timedelta
import json

def handler(event, context):
    """
    Check API Gateway invocations and pause/scale down DSQL if no activity for specified hours
    """
    cluster_resource_id = os.environ['DSQL_CLUSTER_RESOURCE_ID']
    region = os.environ.get('AWS_REGION') or context.invoked_function_arn.split(':')[3]
    api_gateway_id = os.environ.get('API_GATEWAY_ID', '')
    inactivity_hours = int(os.environ.get('INACTIVITY_HOURS', '3'))
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '')
    min_capacity = float(os.environ.get('DSQL_MIN_CAPACITY', '0'))
    
    dsql = boto3.client('dsql', region_name=region)
    cloudwatch = boto3.client('cloudwatch', region_name=region)
    sns = boto3.client('sns', region_name=region) if sns_topic_arn else None
    
    # Check current cluster status
    try:
        cluster = dsql.describe_cluster(ClusterResourceId=cluster_resource_id)
        cluster_status = cluster.get('Status', 'unknown')
        current_min_capacity = cluster.get('ScalingConfiguration', {}).get('MinCapacity', 1)
        
        # If already at minimum capacity or paused, return
        if current_min_capacity <= min_capacity:
            print(f"Cluster {cluster_resource_id} is already at minimum capacity ({current_min_capacity} ACU)")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cluster already at minimum capacity',
                    'status': cluster_status,
                    'min_capacity': current_min_capacity
                })
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
                print(f"Activity detected, keeping cluster at current capacity")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Activity detected, cluster kept at current capacity',
                        'invocations': total_invocations
                    })
                }
        except Exception as e:
            print(f"Warning: Could not check API Gateway metrics: {str(e)}")
            # If we can't check metrics, don't pause the cluster (fail-safe)
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Could not check metrics, keeping cluster at current capacity', 'error': str(e)})
            }
    
    # No activity detected, scale down to minimum capacity
    try:
        print(f"No activity detected for {inactivity_hours} hours, scaling down cluster {cluster_resource_id} to {min_capacity} ACU")
        
        # Get current max capacity from cluster info
        current_max_capacity = cluster.get('ScalingConfiguration', {}).get('MaxCapacity', 2)
        
        # Modify cluster to scale down to minimum capacity
        dsql.modify_cluster(
            ClusterResourceId=cluster_resource_id,
            ScalingConfiguration={
                'MinCapacity': min_capacity,
                'MaxCapacity': current_max_capacity
            }
        )
        
        # Send email notification if SNS topic is configured
        if sns and sns_topic_arn:
            try:
                timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
                subject = f"DSQL Cluster Scaled Down - {cluster_resource_id}"
                message = f"""The Aurora DSQL cluster '{cluster_resource_id}' has been automatically scaled down due to inactivity.

Details:
- Cluster Resource ID: {cluster_resource_id}
- Scaled down at: {timestamp}
- Reason: No API Gateway invocations detected for {inactivity_hours} hours
- New minimum capacity: {min_capacity} ACU
- Region: {region}

The cluster will automatically scale up when API requests are received."""
                
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Subject=subject,
                    Message=message
                )
                print(f"Notification sent to SNS topic: {sns_topic_arn}")
            except Exception as e:
                # Log error but don't fail the Lambda execution
                print(f"Warning: Failed to send notification: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Cluster scaled down due to {inactivity_hours} hours of inactivity',
                'cluster_resource_id': cluster_resource_id,
                'min_capacity': min_capacity
            })
        }
    except Exception as e:
        error_msg = str(e)
        print(f"Error scaling down cluster: {error_msg}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to scale down cluster: {error_msg}'})
        }
EOF
    filename = "index.py"
  }
}

# Lambda function (inline Python code)
resource "aws_lambda_function" "dsql_auto_pause" {
  function_name = var.function_name
  role          = aws_iam_role.dsql_auto_pause.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename         = data.archive_file.dsql_auto_pause_zip.output_path
  source_code_hash = data.archive_file.dsql_auto_pause_zip.output_base64sha256

  environment {
    variables = merge(
      {
        DSQL_CLUSTER_RESOURCE_ID = var.dsql_cluster_resource_id
        # AWS_REGION is automatically provided by Lambda runtime
        API_GATEWAY_ID   = var.api_gateway_id
        INACTIVITY_HOURS = var.inactivity_hours
        DSQL_MIN_CAPACITY = tostring(var.dsql_min_capacity)
      },
      var.admin_email != "" ? {
        SNS_TOPIC_ARN = aws_sns_topic.dsql_auto_pause_notifications[0].arn
      } : {}
    )
  }

  depends_on = [
    aws_iam_role_policy.dsql_auto_pause_logs,
    aws_cloudwatch_log_group.dsql_auto_pause
  ]

  tags = var.tags
}

# EventBridge rule to trigger Lambda every hour
resource "aws_cloudwatch_event_rule" "dsql_auto_pause_schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Trigger DSQL auto-pause check every hour"
  schedule_expression = "rate(1 hour)"

  tags = var.tags
}

# EventBridge target
resource "aws_cloudwatch_event_target" "dsql_auto_pause_target" {
  rule      = aws_cloudwatch_event_rule.dsql_auto_pause_schedule.name
  target_id = "${var.function_name}-target"
  arn       = aws_lambda_function.dsql_auto_pause.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "dsql_auto_pause_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dsql_auto_pause.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dsql_auto_pause_schedule.arn
}
