import json
import boto3
import psycopg2

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
