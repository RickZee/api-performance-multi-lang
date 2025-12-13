# Testing Guide

This document describes how to run and write tests for the metadata service.

## Test Structure

The test suite is organized into several categories:

1. **Integration Tests** (`integration_test.go`) - Full end-to-end tests of the API
2. **Git Sync Tests** (`integration_git_sync_test.go`) - Tests for git repository synchronization
3. **Compatibility Tests** (`integration_compatibility_test.go`) - Tests for backward compatibility checking
4. **Unit Tests** - Component-level tests (to be added in component packages)

## Prerequisites

- Go 1.21+
- Git installed and available in PATH
- Write access to create temporary directories

## Running Tests

### Run All Tests

```bash
make test
# or
go test -v ./...
```

### Run Only Unit Tests (Fast)

```bash
make test-unit
# or
go test -v -short ./...
```

### Run Integration Tests

```bash
make test-integration
# or
go test -v -run TestIntegration ./...
```

### Run Specific Test Suites

```bash
# Git sync tests
make test-integration-git
# or
go test -v -run TestGitSync ./...

# API validation tests
make test-integration-api
# or
go test -v -run TestValidate ./...

# Compatibility tests
make test-integration-compat
# or
go test -v -run TestCompatibility ./...
```

### Run with Coverage

```bash
make test-coverage
# or
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

### Run with Race Detector

```bash
make test-race
# or
go test -race ./...
```

## Test Utilities

The `internal/testutil` package provides utilities for testing:

### `testutil.SetupTestRepo(baseDir)`

Creates a temporary git repository with test schemas. Returns the repository directory path.

```go
repoDir, err := testutil.SetupTestRepo("/tmp")
defer testutil.CleanupTestRepo(repoDir)
```

### `testutil.ValidCarCreatedEvent()`

Returns a valid CarCreated event for testing:

```go
event := testutil.ValidCarCreatedEvent()
```

### `testutil.InvalidEventMissingRequired()`

Returns an invalid event missing required fields.

### `testutil.InvalidEventWrongType()`

Returns an event with incorrect field types.

### `testutil.InvalidEventInvalidPattern()`

Returns an event with invalid pattern (e.g., invalid VIN).

## Test Coverage

### Integration Tests

The integration tests cover:

1. **API Endpoints**:
   - `POST /api/v1/validate` - Single event validation
   - `POST /api/v1/validate/bulk` - Bulk event validation
   - `GET /api/v1/schemas/versions` - List schema versions
   - `GET /api/v1/schemas/:version` - Get specific schema
   - `GET /api/v1/health` - Health check

2. **Validation Scenarios**:
   - Valid events pass validation
   - Invalid events are rejected with detailed errors
   - Bulk validation handles mixed valid/invalid events
   - Schema versioning works correctly

3. **Schema Cache**:
   - Schema loading and caching
   - Version detection
   - Cache invalidation

### Git Sync Tests

Tests for git repository synchronization:

1. **Initial Clone**: Verifies repository is cloned on first sync
2. **Pull Updates**: Verifies new versions are pulled automatically
3. **Error Handling**: Verifies graceful handling of git failures

### Compatibility Tests

Tests for backward compatibility checking:

1. **Non-Breaking Changes**:
   - Adding optional properties
   - Relaxing constraints
   - Adding enum values

2. **Breaking Changes**:
   - Removing required properties
   - Adding new required properties
   - Changing property types
   - Tightening constraints
   - Removing enum values

## Writing New Tests

### Example: Adding a New API Test

```go
func TestValidateEvent_NewScenario(t *testing.T) {
    event := testutil.ValidCarCreatedEvent()
    // Modify event for test scenario
    
    reqBody := map[string]interface{}{
        "event": event,
    }
    
    body, _ := json.Marshal(reqBody)
    req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
    req.Header.Set("Content-Type", "application/json")
    w := httptest.NewRecorder()
    
    router := setupTestRouter()
    router.ServeHTTP(w, req)
    
    // Assertions
    if w.Code != http.StatusOK {
        t.Errorf("Expected status 200, got %d", w.Code)
    }
}
```

### Example: Adding a New Compatibility Test

```go
func TestCompatibility_NewScenario(t *testing.T) {
    checker := compat.NewCompatibilityChecker()
    
    v1Schema := loadTestSchema("v1")
    v2Schema := createV2SchemaWithChanges(v1Schema)
    
    result := checker.CheckCompatibility(v1Schema, v2Schema)
    
    // Assertions
    if result.Compatible != expected {
        t.Errorf("Expected compatible=%v, got %v", expected, result.Compatible)
    }
}
```

## Test Data

Test schemas are created in `internal/testutil/test_repo.go`:

- **v1 schemas**: Basic event and entity schemas
- **Event schema**: Validates event structure with header and entities
- **Entity schemas**: Car entity schema with validation rules

## Continuous Integration

Tests should be run in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run tests
  run: |
    go test -v -race -coverprofile=coverage.out ./...
    go tool cover -func=coverage.out
```

## Troubleshooting

### Tests Fail with "git: command not found"

Ensure git is installed and available in PATH:
```bash
which git
```

### Tests Fail with Permission Errors

Ensure the test has write access to create temporary directories. Tests use `os.MkdirTemp` which should work in most environments.

### Tests Timeout

Some integration tests wait for git operations. If tests timeout:
1. Check git is working: `git --version`
2. Increase timeout values in test files
3. Check disk space for temporary directories

### Schema Loading Fails

If schema loading fails in tests:
1. Verify test repository structure matches expected format
2. Check file permissions on schema files
3. Verify JSON schema syntax is valid

## Best Practices

1. **Cleanup**: Always use `defer` to cleanup test resources
2. **Isolation**: Each test should be independent and not rely on other tests
3. **Naming**: Use descriptive test names: `TestComponent_Scenario_ExpectedResult`
4. **Assertions**: Use clear error messages in assertions
5. **Test Data**: Use test utilities for consistent test data
6. **Coverage**: Aim for high test coverage, especially for critical paths

## Performance Testing

For performance testing, consider:

1. **Load Testing**: Use tools like k6 or Apache Bench
2. **Concurrent Requests**: Test with multiple simultaneous validations
3. **Large Schemas**: Test with complex schemas with many properties
4. **Cache Performance**: Test cache hit/miss scenarios

Example load test:
```bash
# Install k6
brew install k6

# Run load test
k6 run load_test.js
```

