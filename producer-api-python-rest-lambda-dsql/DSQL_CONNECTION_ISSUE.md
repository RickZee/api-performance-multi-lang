# DSQL Connection Issue Investigation

## Problem
Lambda function cannot connect to Aurora DSQL cluster via VPC endpoint. Error: `unable to accept connection, invalid sni`

## Root Cause Analysis

### Current Setup
- **Database**: Aurora DSQL cluster (identifier: `vftmkydwxvxys6asbsc6ih2the`)
- **Connection Method**: VPC Endpoint (PrivateLink)
- **Endpoint DNS**: `vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com`
- **Python Library**: `asyncpg` (asynchronous PostgreSQL driver)
- **SSL Mode**: `require` (tried various configurations)

### Key Findings

1. **AWS DSQL Connectors**: AWS provides official Aurora DSQL Connectors for:
   - Python: Works with `psycopg`/`psycopg2` (synchronous)
   - Node.js: Works with `node-postgres`
   - JDBC: Works with PostgreSQL JDBC driver
   
   **Note**: No official connector for `asyncpg` (asynchronous)

2. **SSL/SNI Requirements**: 
   - DSQL requires SSL for IAM authentication
   - The "invalid sni" error indicates the Server Name Indication (SNI) in the SSL handshake doesn't match what DSQL expects
   - For VPC endpoints, the SNI hostname might need to be the cluster identifier, not the VPC endpoint DNS name

3. **Connection Methods**:
   - **Direct Endpoint**: Format `your-cluster.dsql.us-east-1.on.aws` (for public/private access)
   - **VPC Endpoint**: Uses PrivateLink with custom DNS (for VPC-only access)
   
   We're using VPC endpoint, which requires special SNI handling.

## Attempted Solutions

1. ✅ URL-encoded IAM token in connection string
2. ✅ Used connection parameters instead of connection string
3. ✅ Tried SSL context with `check_hostname=False` and `verify_mode=CERT_NONE`
4. ✅ Tried SSL context with `server_hostname` set to endpoint hostname
5. ✅ Tried SSL context without `server_hostname` (let asyncpg handle it)
6. ✅ Tried `ssl='require'` string mode (same as JDBC `sslmode=require`)

All attempts still result in "invalid sni" error.

## Recommended Solutions

### Option 1: Use AWS DSQL Python Connector (Recommended)
Switch from `asyncpg` to `psycopg2` with AWS DSQL Python Connector:

```python
# Install: pip install aurora_dsql_python_connector psycopg2
import aurora_dsql_psycopg as dsql

config = {
    'host': 'vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com',
    'region': 'us-east-1',
    'user': 'lambda_dsql_user',
    'database': 'car_entities'
}

conn = dsql.connect(**config)
```

**Pros**: Official AWS support, handles IAM tokens automatically
**Cons**: Requires switching from async to sync (would need to refactor FastAPI to use sync endpoints or run in thread pool)

### Option 2: Use Direct Cluster Endpoint (If Available)
If DSQL cluster has a direct endpoint (not VPC endpoint), try connecting to that:

```python
# Format: <cluster-id>.dsql.<region>.on.aws
host = 'vftmkydwxvxys6asbsc6ih2the.dsql.us-east-1.on.aws'
```

**Pros**: Might work with asyncpg if SNI matches cluster identifier
**Cons**: May require public access or different network configuration

### Option 3: Configure asyncpg SSL Context with Cluster Identifier
Try using the cluster identifier as the SNI hostname:

```python
import ssl
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE
# Use cluster identifier for SNI
ssl_context.server_hostname = 'vftmkydwxvxys6asbsc6ih2the.dsql.us-east-1.on.aws'

_pool = await asyncpg.create_pool(
    host='vpce-07acca8bd8980c621-nruuwp08.dsql-fnh4.us-east-1.vpce.amazonaws.com',
    port=5432,
    user=iam_username,
    password=iam_token,
    database=database_name,
    ssl=ssl_context,
)
```

**Pros**: Keeps asyncpg and async code
**Cons**: May not work if DSQL requires VPC endpoint DNS in SNI

### Option 4: Use psycopg2 with Thread Pool (Hybrid)
Keep FastAPI async but use psycopg2 in a thread pool:

```python
from concurrent.futures import ThreadPoolExecutor
import aurora_dsql_psycopg as dsql

executor = ThreadPoolExecutor(max_workers=10)

async def query_database():
    loop = asyncio.get_event_loop()
    conn = await loop.run_in_executor(executor, dsql.connect, config)
    # Use connection...
```

**Pros**: Official AWS connector, keeps async FastAPI
**Cons**: Adds complexity, thread pool overhead

## Next Steps

1. **Check AWS Console/CLI** for DSQL cluster direct endpoint
2. **Test Option 3** (cluster identifier in SNI) first (easiest to try)
3. **If that fails**, consider **Option 1 or 4** (use AWS DSQL connector)
4. **Contact AWS Support** if none work (DSQL is very new, may have undocumented requirements)

## References

- [AWS DSQL Python Connector](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/SECTION_program-with-jupyter.html)
- [DSQL VPC Endpoints](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/privatelink-managing-clusters.html)
- [DSQL Connection Limits](https://dev.classmethod.jp/articles/connect-dsql-from-many-concurrency-lambda/)

