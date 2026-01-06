# Integration Tests Catalog

This document catalogs all existing integration tests in the Metadata Service.

## Test Classes Overview

### 1. FilterE2EIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/FilterE2EIntegrationTest.java`

**Purpose**: End-to-end filter lifecycle testing via REST API

**Test Methods** (8 tests):
- `testCreateFilter` - Creates a filter and verifies status is `pending_approval`
- `testGenerateSQL` - Generates Flink SQL from filter configuration
- `testValidateSQL` - Validates generated SQL syntax
- `testApproveFilter` - Approves filter and verifies status change to `approved`
- `testGetFilterStatus` - Retrieves filter deployment status
- `testListFilters` - Lists all filters for a schema version
- `testUpdateFilter` - Updates filter name and description
- `testDeleteFilter` - Deletes a filter and verifies removal

**Coverage**: Complete filter CRUD operations, SQL generation, approval workflow

---

### 2. JenkinsTriggerIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/JenkinsTriggerIntegrationTest.java`

**Purpose**: Jenkins CI/CD triggering on filter lifecycle events

**Test Methods** (9 tests):
- `testJenkinsTriggeringIsEnabled` - Verifies Jenkins triggering is enabled when configured
- `testCreateFilterTriggersJenkins` - Creates filter and expects Jenkins trigger (currently doesn't verify actual call)
- `testUpdateFilterTriggersJenkins` - Updates filter and expects Jenkins trigger
- `testApproveFilterTriggersJenkins` - Approves filter and expects Jenkins trigger with approver info
- `testDeleteFilterTriggersJenkins` - Deletes filter and expects Jenkins trigger
- `testJenkinsTriggeringCanBeDisabled` - Verifies Jenkins can be disabled via configuration
- `testFilterOperationsSucceedWhenJenkinsFails` - Verifies filter operations succeed even if Jenkins fails
- `testEventSpecificTriggeringCanBeDisabled` - Verifies event-specific triggering can be disabled

**Coverage**: Jenkins triggering configuration, event-specific triggers, error handling

**Current Gap**: Tests don't actually verify Jenkins HTTP calls were made - they only verify filter operations succeed

---

### 3. SpringYamlUpdateIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/SpringYamlUpdateIntegrationTest.java`

**Purpose**: Spring Boot YAML file generation and updates

**Test Methods** (5 tests):
- `testCreateFilterUpdatesYaml` - Verifies filter creation updates filters.yml
- `testUpdateFilterUpdatesYaml` - Verifies filter update updates filters.yml
- `testDeleteFilterUpdatesYaml` - Verifies filter deletion removes filter from filters.yml
- `testYamlFormatMatchesExpectedStructure` - Verifies YAML format and structure
- `testMultipleFiltersInYaml` - Verifies multiple filters are correctly included in YAML

**Coverage**: YAML generation, file updates, format validation, multiple filters handling

---

### 4. ValidationIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/ValidationIntegrationTest.java`

**Purpose**: Schema validation via REST API

**Test Methods** (7 tests):
- `testValidateEvent_Valid` - Validates a valid event
- `testValidateEvent_Invalid` - Validates an invalid event (missing required fields)
- `testValidateBulkEvents` - Validates multiple events in bulk
- `testGetVersions` - Retrieves available schema versions
- `testGetSchema` - Retrieves event schema by version
- `testGetSchema_Entity` - Retrieves entity schema (car) by version
- `testHealth` - Health check endpoint

**Coverage**: Single and bulk validation, schema retrieval, health checks

---

### 5. ApiErrorHandlingIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/ApiErrorHandlingIntegrationTest.java`

**Purpose**: API error handling and validation error scenarios

**Test Methods** (18 tests):
- `testValidateEvent_InvalidJSON` - Invalid JSON format
- `testValidateEvent_MissingEventField` - Missing required event field
- `testValidateEvent_WrongContentType` - Wrong Content-Type header
- `testValidateEvent_WrongHTTPMethod` - Wrong HTTP method (GET, PUT, DELETE on POST endpoint)
- `testValidateBulkEvents_EmptyArray` - Empty events array
- `testValidateBulkEvents_InvalidJSON` - Invalid JSON in bulk request
- `testGetSchema_InvalidVersionFormat` - Invalid schema version format
- `testGetSchema_MissingTypeParameter` - Missing type parameter (defaults to event)
- `testGetSchema_NonExistentVersion` - Non-existent schema version
- `testCreateFilter_InvalidRequest` - Invalid filter creation requests (missing fields, empty values)
- `testGetFilter_InvalidId` - Invalid filter ID (path traversal attempt)
- `testUpdateFilter_NotFound` - Update non-existent filter
- `testDeleteFilter_NotFound` - Delete non-existent filter
- `testGenerateSQL_NotFound` - Generate SQL for non-existent filter
- `testApproveFilter_NotFound` - Approve non-existent filter
- `testValidateEvent_ExplicitVersion` - Explicit version specification
- `testValidateEvent_InvalidVersion` - Invalid version specification
- `testValidateBulkEvents_MissingEventsField` - Missing events field in bulk request

**Coverage**: Comprehensive error handling, validation errors, security (path traversal), not found scenarios

---

### 6. MultiVersionValidationIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/MultiVersionValidationIntegrationTest.java`

**Purpose**: Multi-version schema validation

**Test Methods** (4 tests):
- `testValidateEvent_ExplicitVersion` - Validates event with explicit version
- `testValidateEvent_DefaultVersion` - Validates event with default version (no version specified)
- `testValidateEvent_InvalidVersion` - Validates event with invalid version
- `testValidateEvent_LatestVersion` - Validates event with "latest" version

**Coverage**: Version handling, default version, latest version, invalid version handling

---

### 7. GitSyncIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/GitSyncIntegrationTest.java`

**Purpose**: Git repository synchronization

**Test Methods** (4 tests):
- `testGitSync_InitialSync` - Initial repository synchronization
- `testGitSync_GetLocalDir` - Retrieves local cache directory
- `testGitSync_LocalRepository` - Local file:// repository access
- `testGitSync_Stop` - Service stop functionality

**Coverage**: Initial sync, local directory access, local repository handling

---

### 8. GitSyncEdgeCasesIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/GitSyncEdgeCasesIntegrationTest.java`

**Purpose**: Git sync edge cases and error handling

**Test Methods** (4 tests):
- `testGitSync_RepositoryWithExistingFiles` - Sync with existing files in cache
- `testGitSync_LocalFileRepository` - Local file:// repository handling
- `testGitSync_HandlesMissingRepository` - Missing repository handling (documented)
- `testGitSync_GetLocalDirReturnsCorrectPath` - Local directory path verification

**Coverage**: Edge cases, existing files, path verification

---

## Test Coverage Summary

| Category | Test Count | Coverage |
|----------|------------|----------|
| Filter Lifecycle | 8 | Create, Read, Update, Delete, Approve, Generate SQL, Validate SQL, Status |
| Jenkins CI/CD | 9 | Triggering on all events, configuration, error handling |
| Spring YAML | 5 | Generation, updates, format, multiple filters |
| Schema Validation | 7 | Single, bulk, schema retrieval, health |
| Error Handling | 18 | Invalid requests, not found, security, validation errors |
| Multi-Version | 4 | Version handling, defaults, latest |
| Git Sync | 4 | Initial sync, local access, directory handling |
| Git Sync Edge Cases | 4 | Existing files, missing repo, path verification |
| **Total** | **60** | **Comprehensive coverage** |

---

## Test Infrastructure

### Common Test Setup
- Uses H2 in-memory database for all tests
- Test repository setup via `TestRepoSetup`
- Temporary directories for test isolation
- Git sync disabled in test mode (`test.mode=true`)
- Manual schema copying for test setup

### Test Utilities
- `TestRepoSetup` - Creates test Git repository structure
- `TestEventGenerator` - Generates test events for validation

### Test Configuration
- All tests use `@SpringBootTest` with random port for web tests
- Dynamic property configuration via `@DynamicPropertySource`
- SQL scripts for database setup (`schema-test.sql`)

---

## Gaps and Improvements Needed

1. **Jenkins Verification**: Current Jenkins tests don't verify actual HTTP calls to Jenkins
2. **Workflow Integration**: No comprehensive end-to-end workflow tests combining all components
3. **CI/CD Emulation**: No local Jenkins mock server for testing without real Jenkins
4. **Confluent Cloud Mock**: Filter deployment tests don't verify Confluent Cloud API calls

---

**Last Updated**: 2025-12-30
**Total Integration Tests**: 60

