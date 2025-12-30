# Filter Storage Migration Guide

This guide covers the migration from file-based filter storage (JSON files in Git) to PostgreSQL database storage.

## Overview

The Metadata Service has been enhanced to store filter configurations in PostgreSQL instead of JSON files. This provides:

- Better concurrency support for multiple service instances
- Improved querying and filtering capabilities
- Production-ready persistence with ACID transactions
- Dynamic filter reloading for CDC Streaming Service

## Pre-Migration Checklist

- [ ] PostgreSQL database is available and accessible
- [ ] Database credentials are configured
- [ ] Flyway migrations are enabled
- [ ] Backup of existing filter files has been created
- [ ] All service instances are on the same version

## Migration Steps

### Step 1: Database Setup

1. Create PostgreSQL database:
```sql
CREATE DATABASE metadata_service;
```

2. Configure database connection in `application.yml` or via environment variables:
```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/metadata_service
    username: postgres
    password: postgres
  flyway:
    enabled: true
```

3. Start the service - Flyway will automatically create the `filters` table on first startup.

### Step 2: Enable Dual-Write Mode (Optional)

During migration, you can enable dual-write mode to write filters to both database and files:

```yaml
filter:
  storage:
    dual-write: true
    fallback-to-files: true
```

This ensures backward compatibility during the transition period.

### Step 3: Migrate Existing Filters

If you have existing filters in JSON files, you can migrate them using one of these approaches:

**Option A: Automatic Migration (Recommended)**
- The service will automatically read from files if the database is empty (when `filter.storage.fallback-to-files=true`)
- Create filters via API - they will be stored in the database
- Existing filters in files will be read until migrated

**Option B: Manual Migration Script**
- Create a migration script that reads filters from JSON files
- Calls the Metadata Service API to create filters in the database
- Validates that all filters were migrated successfully

### Step 4: Verify Migration

1. Check that filters are stored in database:
```sql
SELECT COUNT(*) FROM filters;
SELECT schema_version, COUNT(*) FROM filters GROUP BY schema_version;
```

2. Test filter operations via API:
```bash
# List filters
curl http://localhost:8080/api/v1/filters?version=v1

# Get active filters (used by CDC Streaming Service)
curl http://localhost:8080/api/v1/filters/active?schemaVersion=v1
```

3. Verify CDC Streaming Service can fetch filters:
```bash
# Check if Metadata Service is accessible
curl http://localhost:8080/api/v1/health
```

### Step 5: Disable File Fallback

Once migration is complete and verified:

1. Set `filter.storage.fallback-to-files=false` in `application.yml`
2. Restart the service
3. Verify all operations use database only

### Step 6: Disable Dual-Write (If Enabled)

If you enabled dual-write mode:

1. Set `filter.storage.dual-write=false` in `application.yml`
2. Restart the service
3. Filters will only be written to database

## Rollback Procedure

If you need to rollback to file-based storage:

1. Stop the service
2. Set `filter.storage.fallback-to-files=true`
3. Ensure filters exist in JSON files (restore from backup if needed)
4. Restart the service
5. The service will read from files if database is unavailable

## Post-Migration

After successful migration:

- Filters are stored in PostgreSQL
- Schema versioning remains in Git (unchanged)
- CDC Streaming Service can dynamically reload filters without restart
- Multiple service instances can update filters concurrently

## Troubleshooting

### Database Connection Issues

If the service cannot connect to PostgreSQL:
- Check database credentials
- Verify network connectivity
- Check PostgreSQL logs for connection errors
- Service will fall back to files if `fallback-to-files=true`

### Migration Errors

If filters fail to migrate:
- Check service logs for detailed error messages
- Verify filter JSON structure matches expected format
- Ensure schema versions match Git folder structure
- Re-run migration for failed filters

### Performance Issues

If query performance degrades:
- Verify indexes are created: `\d filters` in psql
- Check query execution plans
- Consider adding additional indexes if needed
- Monitor database connection pool usage

## Support

For issues or questions:
- Check service logs: `docker logs metadata-service-java`
- Review database logs for PostgreSQL errors
- Verify configuration in `application.yml`
- Check API health endpoint: `GET /api/v1/health`

