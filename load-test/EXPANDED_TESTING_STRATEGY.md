# Expanded Performance & Security-Aware Testing Strategy

## Implementation Status

This document tracks the implementation of the expanded testing strategy that adds production-like concerns to the performance testing framework.

## Phase 1: Instrumentation & Observability ✅ (Partially Complete)

### Completed
- ✅ **PostgreSQL pg_stat_statements Integration**
  - Enabled `pg_stat_statements` extension in `docker-compose.yml`
  - Created `query_performance_summary` view in `postgres/init-large.sql`
  - Configured Postgres to track all queries with 10,000 query limit

- ✅ **Database Query Metrics Collection**
  - Created `load-test/shared/collect-db-metrics.py` script to collect:
    - Top queries by total execution time
    - Connection pool statistics (active, idle, waiting connections)
    - Query performance metrics (mean, min, max, stddev, cache hit ratio)
  - Integrated into test execution script (`run-sequential-throughput-tests.sh`)
  - Automatically resets `pg_stat_statements` before each test run

- ✅ **Metrics Database Schema Extension**
  - Created migration `002_add_db_query_metrics.sql` with tables:
    - `db_query_metrics_snapshots` - Stores snapshot metadata
    - `db_query_details` - Stores individual query performance metrics
    - `db_connection_pool_stats` - Stores connection pool statistics
  - Extended `db_client.py` with functions to store and retrieve DB query metrics

- ✅ **HTML Report Enhancement**
  - Added "Database Query Performance Metrics" section to HTML reports
  - Displays top 10 queries per API with execution time, cache hit ratio, etc.
  - Shows connection pool statistics per API
  - Only displayed for full/saturation tests (not smoke tests)

### Pending
- ⏳ API-level instrumentation hooks for DB timing (currently using pg_stat_statements only)
- ⏳ Structured logging for auth/secrets timing (depends on Phase 2)

## Phase 2: Secrets & Auth Test Modes 🚧 (Partially Complete)

### Completed
- ✅ **Mock Secrets Service**
  - Created `load-test/shared/secrets-mock-service.py` HTTP server
  - Simulates remote secrets store (AWS Secrets Manager-like)
  - Supports configurable delays, failure rates, and timeouts
  - Provides secrets via REST API (`/secrets/{name}`)

- ✅ **JWT Test Helper**
  - Created `load-test/shared/jwt-test-helper.py` for generating test tokens
  - Supports valid, expired, and invalid tokens
  - Configurable user ID, roles, expiration

- ✅ **k6 Test Script Updates**
  - Added `AUTH_ENABLED` and `JWT_TOKEN` environment variable support
  - Updated REST API test script to include Authorization header when enabled

- ✅ **Go REST API Auth Middleware (Proof of Concept)**
  - Created `producer-api-go-rest/internal/middleware/auth.go`
  - Added `AUTH_ENABLED` and `JWT_SECRET_KEY` configuration
  - Basic JWT middleware structure (placeholder for full validation)
  - Health check endpoint remains public

### Pending
- ⏳ Complete JWT validation implementation (signature verification, expiration check)
- ⏳ Implement secrets abstraction in APIs (env vars vs remote)
- ⏳ Add auth/secrets to other APIs (Java, Rust)
- ⏳ Add test profiles to `run-sequential-throughput-tests.sh`:
  - `no-auth` (baseline)
  - `auth-jwt-only` (JWT validation only)
  - `auth-jwt+db-authz` (JWT + DB permission lookup)
  - `secrets-remote` (remote secrets retrieval)
- ⏳ Add metrics collection for auth/secrets timing

## Phase 3: DB-Focused Analysis & Reporting ✅ (Complete)

### Completed
- ✅ DB query metrics collection and storage
- ✅ HTML report sections for top queries and connection pool stats
- ✅ Integration with existing test execution pipeline

### Future Enhancements
- ⏳ Per-request DB time breakdown
- ⏳ Query efficiency metrics (queries per request)
- ⏳ Lock contention analysis
- ⏳ N+1 query pattern detection

## Phase 4: Cloud Stack Integration ⏳ (Not Started)

### Planned
- Wire k6 tests to Terraform-provisioned API Gateway endpoints
- Compare local Docker vs cloud Lambda performance
- Measure cold-start impact with secrets + auth enabled
- Cost comparison (Lambda/APIGW vs EKS)

## Phase 5: Resilience & Fault Injection ⏳ (Not Started)

### Planned
- DB latency spike injection (via `pg_sleep` or network delays)
- Secret store failure simulation
- Auth service latency simulation
- Recovery time measurement
- Error rate spike analysis

## Usage Examples

### Running Tests with DB Metrics Collection

DB metrics are automatically collected for full and saturation tests:

```bash
cd load-test/shared
./run-sequential-throughput-tests.sh full
```

The HTML report will include a "Database Query Performance Metrics" section showing:
- Top 10 queries per API by total execution time
- Connection pool statistics
- Query cache hit ratios

### Running Tests with Authentication (Future)

Once auth is implemented in APIs:

```bash
# Generate test JWT token
TOKEN=$(python3 load-test/shared/jwt-test-helper.py generate)

# Run tests with auth enabled
AUTH_ENABLED=true JWT_TOKEN=$TOKEN ./run-sequential-throughput-tests.sh full
```

### Running Tests with Remote Secrets (Future)

Once secrets abstraction is implemented:

```bash
# Start mock secrets service
python3 load-test/shared/secrets-mock-service.py 8080 &

# Run tests with remote secrets
SECRETS_MODE=remote SECRETS_SERVICE_URL=http://localhost:8080 ./run-sequential-throughput-tests.sh full
```

## Next Steps

1. **Complete Phase 2**: Implement auth and secrets in at least one API (Go REST) as proof of concept
2. **Add Test Profiles**: Extend test execution script to support different auth/secrets modes
3. **Cloud Integration**: Wire Terraform stack into test harness
4. **Fault Injection**: Add controlled failure scenarios to test resilience

## Files Modified/Created

### New Files
- `load-test/shared/collect-db-metrics.py` - DB query metrics collection
- `load-test/shared/secrets-mock-service.py` - Mock secrets store
- `load-test/shared/jwt-test-helper.py` - JWT token generation
- `load-test/shared/migrations/002_add_db_query_metrics.sql` - DB metrics schema
- `load-test/EXPANDED_TESTING_STRATEGY.md` - This document

### Modified Files
- `docker-compose.yml` - Enabled pg_stat_statements in Postgres, added command config for postgres-metrics
- `postgres/init-large.sql` - Added pg_stat_statements extension and query_performance_summary view
- `load-test/shared/db_client.py` - Added DB query metrics functions (insert_db_query_metrics_snapshot, get_db_query_metrics_snapshot, get_all_apis_db_query_metrics)
- `load-test/shared/run-sequential-throughput-tests.sh` - Integrated DB metrics collection, added pg_stat_statements reset
- `load-test/shared/generate-html-report.py` - Added DB query metrics section to HTML reports
- `load-test/k6/config.js` - Added AUTH_ENABLED, SECRETS_MODE, JWT_TOKEN configuration
- `load-test/k6/rest-api-test.js` - Added JWT token support in Authorization header
- `producer-api-go-rest/internal/config/config.go` - Added AuthEnabled and JWTSecretKey configuration
- `producer-api-go-rest/cmd/server/main.go` - Integrated JWT auth middleware
- `producer-api-go-rest/internal/middleware/auth.go` - Created (new file) JWT auth middleware placeholder

