# Lambda function to grant IAM role access to DSQL IAM user
# This is needed because DSQL requires IAM authentication even for admin operations

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Role for the Lambda function
resource "aws_iam_role" "dsql_iam_grant" {
  name = "${var.project_name}-dsql-iam-grant-role"

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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.dsql_iam_grant.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for DSQL admin access (to grant IAM role mappings)
resource "aws_iam_role_policy" "dsql_admin" {
  name = "${var.project_name}-dsql-iam-grant-admin"
  role = aws_iam_role.dsql_iam_grant.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin"
        ]
        Resource = "arn:aws:dsql:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.dsql_cluster_resource_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function code (Python script to grant IAM access)
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/dsql-iam-grant-lambda.zip"

  source {
    content = <<-PYTHON
import json
import boto3
import psycopg2
from psycopg2 import sql

def lambda_handler(event, context):
    """
    Grants IAM role access to DSQL IAM user.
    
    Event structure:
    {
        "dsql_host": "cluster-id.dsql-suffix.region.on.aws",
        "iam_user": "dsql_iam_user",
        "role_arn": "arn:aws:iam::account:role/role-name"
    }
    """
    dsql_host = event.get('dsql_host')
    iam_user = event.get('iam_user')
    role_arn = event.get('role_arn')
    region = event.get('region', 'us-east-1')
    
    if not all([dsql_host, iam_user, role_arn]):
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Missing required parameters'})
        }
    
    try:
        # Generate IAM authentication token for postgres user
        rds_client = boto3.client('rds', region_name=region)
        token = rds_client.generate_db_auth_token(
            DBHostname=dsql_host,
            Port=5432,
            DBUsername='postgres',
            Region=region
        )
        
        # Connect to DSQL
        conn = psycopg2.connect(
            host=dsql_host,
            port=5432,
            database='postgres',
            user='postgres',
            password=token,
            sslmode='require'
        )
        
        cur = conn.cursor()
        
        # Grant IAM role access
        grant_sql = f"AWS IAM GRANT {iam_user} TO '{role_arn}';"
        cur.execute(grant_sql)
        
        # Verify the mapping
        cur.execute("""
            SELECT pg_role_name, arn 
            FROM sys.iam_pg_role_mappings 
            WHERE pg_role_name = %s
        """, (iam_user,))
        
        result = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'IAM role mapping granted successfully',
                'mappings': [{'role': r[0], 'arn': r[1]} for r in result]
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
PYTHON
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "dsql_iam_grant" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-dsql-iam-grant"
  role            = aws_iam_role.dsql_iam_grant.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DSQL_HOST = var.dsql_host
    }
  }

  tags = var.tags
}

# Note: This Lambda function requires:
# 1. psycopg2 Lambda layer (or package it in the deployment)
# 2. The Lambda's IAM role must be mapped to postgres user in DSQL first:
#    AWS IAM GRANT postgres TO 'arn:aws:iam::ACCOUNT:role/PROJECT-dsql-iam-grant-role';
#
# Once the Lambda role is mapped, this function can grant other IAM roles automatically.
# For now, the function is created but the initial postgres mapping must be done manually.
