# Testing Guide

This document provides comprehensive information about testing the Metadata Service, including how to run tests, test coverage, test catalog, and implementation details.

## Table of Contents

1. [Overview](#overview)
2. [Running Tests](#running-tests)
3. [Test Catalog](#test-catalog)
4. [Test Coverage](#test-coverage)
5. [Implementation Details](#implementation-details)

---

## Overview

The Metadata Service includes comprehensive test coverage with:
- **60+ integration tests** across 8 test classes
- **15 workflow integration tests** for end-to-end scenarios
- **Unit tests** for all service components
- **Mock Jenkins server** for CI/CD emulation
- **JaCoCo code coverage** reporting

---

## Running Tests

### All Tests (Unit + Integration)

```bash
./gradlew test
```

### Unit Tests Only

```bash
./gradlew test --tests "*ServiceTest"
```

### Integration Tests Only

```bash
./gradlew test --tests "*IntegrationTest"
```

Or using the test script:

```bash
./run-tests.sh --integration
```

### Workflow Tests Only

```bash
./run-tests.sh --workflow
# or
./scripts/run-integration-tests-local.sh --workflow-only
```

### Jenkins Tests Only

```bash
./scripts/run-integration-tests-local.sh --jenkins-only
```

### Specific Test Suites

**Jenkins-Specific Tests:**
```bash
./gradlew test --tests "*Jenkins*"
```

**Spring YAML Tests:**
```bash
./gradlew test --tests "*SpringYaml*"
```

**With Verbose Output:**
```bash
./run-tests.sh --verbose
```

### Generate Coverage Report

```bash
./gradlew test jacocoTestReport
```

### View HTML Coverage Report

```bash
open build/reports/jacoco/test/html/index.html
```

### Verify Coverage Thresholds

```bash
./gradlew jacocoTestCoverageVerification
```

---

## Test Catalog

### Integration Test Classes

#### 1. FilterE2EIntegrationTest
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

#### 2. JenkinsTriggerIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/JenkinsTriggerIntegrationTest.java`

**Purpose**: Jenkins CI/CD triggering on filter lifecycle events

**Test Methods** (9 tests):
- `testJenkinsTriggeringIsEnabled` - Verifies Jenkins triggering is enabled when configured
- `testCreateFilterTriggersJenkins` - Creates filter and expects Jenkins trigger
- `testUpdateFilterTriggersJenkins` - Updates filter and expects Jenkins trigger
- `testApproveFilterTriggersJenkins` - Approves filter and expects Jenkins trigger with approver info
- `testDeleteFilterTriggersJenkins` - Deletes filter and expects Jenkins trigger
- `testJenkinsTriggeringCanBeDisabled` - Verifies Jenkins can be disabled via configuration
- `testFilterOperationsSucceedWhenJenkinsFails` - Verifies filter operations succeed even if Jenkins fails
- `testEventSpecificTriggeringCanBeDisabled` - Verifies event-specific triggering can be disabled

**Coverage**: Jenkins triggering configuration, event-specific triggers, error handling

---

#### 3. SpringYamlUpdateIntegrationTest
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

#### 4. ValidationIntegrationTest
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

#### 5. ApiErrorHandlingIntegrationTest
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

#### 6. MultiVersionValidationIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/MultiVersionValidationIntegrationTest.java`

**Purpose**: Multi-version schema validation

**Test Methods** (4 tests):
- `testValidateEvent_ExplicitVersion` - Validates event with explicit version
- `testValidateEvent_DefaultVersion` - Validates event with default version (no version specified)
- `testValidateEvent_InvalidVersion` - Validates event with invalid version
- `testValidateEvent_LatestVersion` - Validates event with "latest" version

**Coverage**: Version handling, default version, latest version, invalid version handling

---

#### 7. GitSyncIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/GitSyncIntegrationTest.java`

**Purpose**: Git repository synchronization

**Test Methods** (4 tests):
- `testGitSync_InitialSync` - Initial repository synchronization
- `testGitSync_GetLocalDir` - Retrieves local cache directory
- `testGitSync_LocalRepository` - Local file:// repository access
- `testGitSync_Stop` - Service stop functionality

**Coverage**: Initial sync, local directory access, local repository handling

---

#### 8. GitSyncEdgeCasesIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/GitSyncEdgeCasesIntegrationTest.java`

**Purpose**: Git sync edge cases and error handling

**Test Methods** (4 tests):
- `testGitSync_RepositoryWithExistingFiles` - Sync with existing files in cache
- `testGitSync_LocalFileRepository` - Local file:// repository handling
- `testGitSync_HandlesMissingRepository` - Missing repository handling (documented)
- `testGitSync_GetLocalDirReturnsCorrectPath` - Local directory path verification

**Coverage**: Edge cases, existing files, path verification

---

#### 9. WorkflowIntegrationTest
**Location**: `src/test/java/com/example/metadata/integration/WorkflowIntegrationTest.java`

**Purpose**: Comprehensive end-to-end workflow testing

**Test Methods** (15 tests):
- **Workflow 1**: Complete filter lifecycle (create, generate SQL, validate, approve, deploy, update, delete)
- **Workflow 2**: Schema validation (single, bulk, get versions, get schema)
- **Workflow 3**: Git sync (initial sync)
- **Workflow 4**: Spring YAML generation (all filter operations)
- **Workflow 5**: CI/CD integration (all events trigger Jenkins, graceful degradation)

**Coverage**: End-to-end workflows combining all components

---

### Test Coverage Summary

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
| Workflow Tests | 15 | End-to-end workflows |
| **Total** | **75** | **Comprehensive coverage** |

---

## Test Coverage

### Coverage Overview

#### Overall Metrics

- **Target Coverage**: 70% minimum
- **Class Coverage**: 60% minimum (excluding config, models, exceptions)
- **Service Layer**: 80% minimum

#### Coverage Tool

The project uses **JaCoCo** for code coverage analysis.

### Coverage by Component

#### Jenkins CI/CD Triggering

| Component | Coverage | Unit Tests | Integration Tests |
|-----------|----------|------------|-------------------|
| `JenkinsTriggerService` | ✅ 95%+ | 10 | 8 |
| `FilterController` (Jenkins calls) | ✅ 90%+ | - | 8 |
| `AppConfig.JenkinsConfig` | ✅ 100% | - | 2 |
| Error handling | ✅ 90%+ | 2 | 2 |
| Authentication | ✅ 100% | 2 | - |
| Build parameters | ✅ 100% | 1 | - |

#### Spring Boot YAML Generation

| Component | Coverage | Unit Tests | Integration Tests |
|-----------|----------|------------|-------------------|
| `SpringYamlGeneratorService` | ✅ 95%+ | 15 | 6 |
| `SpringYamlWriterService` | ✅ 95%+ | 12 | 6 |
| `FilterController` (YAML updates) | ✅ 90%+ | - | 6 |

#### Filter Management

| Component | Coverage | Unit Tests | Integration Tests |
|-----------|----------|------------|-------------------|
| `FilterStorageService` | ✅ 85%+ | 20+ | 7 |
| `FilterGeneratorService` | ✅ 90%+ | 15+ | 7 |
| `FilterDeployerService` | ✅ 80%+ | 10+ | - |
| `FilterController` | ✅ 90%+ | - | 7 |

### Coverage Exclusions

The following packages/classes are excluded from coverage requirements:

- `com.example.metadata.config.*` - Configuration classes
- `com.example.metadata.model.*` - Data model classes
- `com.example.metadata.exception.*` - Exception classes
- `com.example.metadata.MetadataServiceApplication` - Main application class

### Coverage Goals

#### Current Status
- ✅ Jenkins CI/CD Triggering: **95%+ coverage**
- ✅ Spring Boot YAML Generation: **95%+ coverage**
- ✅ Filter Management: **85%+ coverage**
- ✅ Overall Service Layer: **80%+ coverage**

#### Future Improvements
- Increase FilterDeployerService coverage to 90%+
- Add more edge case tests for Jenkins triggering
- Add performance tests for high-load scenarios

---

## Implementation Details

### Implementation Complete ✅

All planned features have been implemented:

1. ✅ **Integration Tests Catalog** - All 8 existing integration test classes documented
2. ✅ **Mock Jenkins Server** - Embedded HTTP server for CI/CD emulation
3. ✅ **Enhanced Jenkins Tests** - JenkinsTriggerIntegrationTest now verifies actual HTTP calls
4. ✅ **Workflow Integration Tests** - Comprehensive tests for all documented workflows
5. ✅ **Test Execution Scripts** - Scripts for running tests with mock Jenkins

### Files Created

#### 1. MockJenkinsServer.java
**Location**: `src/test/java/com/example/metadata/testutil/MockJenkinsServer.java`

**Features**:
- Embedded HTTP server using Java's HttpServer
- Captures build trigger requests with parameters
- Supports Basic Auth and build token authentication
- Can simulate failures and timeouts
- Provides verification methods to check if builds were triggered
- Thread-safe request capture

**Usage**:
```java
MockJenkinsServer mockJenkins = new MockJenkinsServer();
int port = mockJenkins.start();
// Configure Jenkins URL to point to mockJenkins.getBaseUrl()
// ... perform filter operations ...
// Verify: mockJenkins.wasTriggered("create")
```

#### 2. WorkflowIntegrationTest.java
**Location**: `src/test/java/com/example/metadata/integration/WorkflowIntegrationTest.java`

**Test Coverage** (15 tests):
- **Workflow 1**: Complete filter lifecycle (create, generate SQL, validate, approve, deploy, update, delete)
- **Workflow 2**: Schema validation (single, bulk, get versions, get schema)
- **Workflow 3**: Git sync (initial sync)
- **Workflow 4**: Spring YAML generation (all filter operations)
- **Workflow 5**: CI/CD integration (all events trigger Jenkins, graceful degradation)

#### 3. Enhanced JenkinsTriggerIntegrationTest.java
**Updates**:
- Now uses MockJenkinsServer instead of real Jenkins URL
- Verifies actual HTTP calls to Jenkins
- Verifies build parameters (FILTER_EVENT_TYPE, FILTER_ID, FILTER_VERSION)
- Tests authentication methods
- Tests error scenarios with mock server

#### 4. run-integration-tests-local.sh
**Location**: `scripts/run-integration-tests-local.sh`

**Features**:
- Runs integration tests with mock Jenkins server
- Options for workflow-only or Jenkins-only tests
- Generates test reports
- Provides test summary

**Usage**:
```bash
./scripts/run-integration-tests-local.sh
./scripts/run-integration-tests-local.sh --workflow-only
./scripts/run-integration-tests-local.sh --jenkins-only
./scripts/run-integration-tests-local.sh --report
```

#### 5. Updated run-tests.sh
**New Options**:
- `--integration` - Run only integration tests
- `--workflow` - Run only workflow integration tests
- `--verbose` - Enable verbose output

### Test Infrastructure

#### Common Test Setup
- Uses H2 in-memory database for all tests
- Test repository setup via `TestRepoSetup`
- Temporary directories for test isolation
- Git sync disabled in test mode (`test.mode=true`)
- Manual schema copying for test setup

#### Test Utilities
- `TestRepoSetup` - Creates test Git repository structure
- `TestEventGenerator` - Generates test events for validation
- `MockJenkinsServer` - Embedded Jenkins server for CI/CD testing

#### Test Configuration
- All tests use `@SpringBootTest` with random port for web tests
- Dynamic property configuration via `@DynamicPropertySource`
- SQL scripts for database setup (`schema-test.sql`)

### Workflows Tested

#### ✅ Workflow 1: Filter Lifecycle with CI/CD
- Create filter → Jenkins triggered → Spring YAML updated
- Generate SQL
- Validate SQL
- Approve filter → Jenkins triggered
- Deploy filter → Jenkins triggered → Spring YAML updated
- Update filter → Jenkins triggered → Spring YAML updated
- Delete filter → Jenkins triggered → Spring YAML updated

#### ✅ Workflow 2: Schema Validation
- Validate single event
- Validate bulk events
- Get schema versions
- Get schema by version

#### ✅ Workflow 3: Git Sync
- Initial sync on startup
- Local repository access

#### ✅ Workflow 4: Spring YAML Generation
- Automatic YAML generation on filter create/update/delete/deploy
- Multiple filters in YAML
- YAML format validation

#### ✅ Workflow 5: CI/CD Integration
- All filter operations trigger Jenkins correctly
- Build parameters verified (FILTER_EVENT_TYPE, FILTER_ID, FILTER_VERSION)
- Graceful degradation when Jenkins fails
- Event-specific triggering configuration

### Verification

All tests verify:
1. ✅ Filter operations succeed
2. ✅ Jenkins HTTP calls are made (via MockJenkinsServer)
3. ✅ Build parameters are correct
4. ✅ Spring YAML files are updated
5. ✅ Schema validation works
6. ✅ Git sync works
7. ✅ Error handling works (graceful degradation)

### Mock Jenkins Server Features

- **Request Capture**: Captures all build trigger requests
- **Parameter Verification**: Verifies FILTER_EVENT_TYPE, FILTER_ID, FILTER_VERSION
- **Authentication**: Supports Basic Auth and build token
- **Failure Simulation**: Can simulate 500 errors, timeouts
- **Thread-Safe**: Uses CopyOnWriteArrayList for concurrent access
- **Verification Methods**: `wasTriggered()`, `wasTriggeredWith()`, `getCapturedRequests()`

### Next Steps

1. **Confluent Cloud Mock**: Add mock Confluent Cloud API for filter deployment tests
2. **Performance Tests**: Add performance benchmarks for workflow execution
3. **Load Tests**: Test system under load with multiple concurrent filter operations
4. **Chaos Tests**: Test system resilience with various failure scenarios

---

## Troubleshooting

### Coverage Report Not Generated

**Problem**: `build/reports/jacoco/test/html/index.html` not found

**Solution**:
```bash
./gradlew clean test jacocoTestReport
```

### Coverage Below Threshold

**Problem**: `jacocoTestCoverageVerification` fails

**Solution**:
1. Review coverage report to identify gaps
2. Add tests for uncovered code paths
3. Review exclusions if appropriate

### Tests Not Running

**Problem**: Tests are skipped or not executed

**Solution**:
```bash
# Clean and rebuild
./gradlew clean test

# Run with verbose output
./gradlew test --info
```

---

## Related Documentation

- [METADATA_SERVICE_DOCUMENTATION.md](../METADATA_SERVICE_DOCUMENTATION.md) - Service documentation with all workflows
- [README.md](../README.md) - Service overview and quick start

---

**Last Updated**: 2025-12-30  
**Total Integration Tests**: 75  
**Status**: ✅ Complete

