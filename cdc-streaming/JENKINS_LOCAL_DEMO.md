# Local Jenkins CI/CD Demo Guide

This guide explains how to run and demonstrate the CI/CD pipeline locally, simulating Jenkins behavior without requiring an actual Jenkins server.

## Quick Start

### 1. Run Setup Check

```bash
cd cdc-streaming
./scripts/setup-jenkins-local.sh
```

This verifies all prerequisites are installed and configured.

### 2. Run Complete CI/CD Demo

```bash
./scripts/demo-ci-cd.sh
```

This runs the complete pipeline simulation end-to-end.

## Scripts Overview

### `setup-jenkins-local.sh`

Verifies prerequisites for local Jenkins simulation:

- Docker and Docker Compose
- Java 17+
- Gradle wrapper
- Port availability
- Project structure

**Usage:**
```bash
./scripts/setup-jenkins-local.sh
```

### `jenkins-local-simulate.sh`

Simulates Jenkins pipeline stages locally. This is the main script that mimics Jenkins behavior.

**Usage:**
```bash
# Run complete pipeline
./scripts/jenkins-local-simulate.sh

# Run specific stage
./scripts/jenkins-local-simulate.sh --stage build
./scripts/jenkins-local-simulate.sh --stage test-local

# Run specific test suite
./scripts/jenkins-local-simulate.sh --test-suite local
./scripts/jenkins-local-simulate.sh --test-suite schema
./scripts/jenkins-local-simulate.sh --test-suite breaking

# Skip Docker builds (use cached images)
./scripts/jenkins-local-simulate.sh --skip-build

# Keep containers running after tests
./scripts/jenkins-local-simulate.sh --no-cleanup

# Verbose output
./scripts/jenkins-local-simulate.sh --verbose
```

**Available Stages:**
- `checkout` - Checkout source code
- `prerequisites` - Verify prerequisites
- `build` - Build Docker images
- `infrastructure` - Start Kafka, Schema Registry, Mock API
- `services` - Start Metadata Service and Stream Processor
- `test-local` - Run local integration tests
- `test-schema` - Run schema evolution tests
- `test-breaking` - Run breaking schema change tests
- `reports` - Generate test reports

### `demo-ci-cd.sh`

Complete CI/CD demo script that runs setup check and pipeline simulation.

**Usage:**
```bash
# Full demo
./scripts/demo-ci-cd.sh

# Fast demo (skip builds)
./scripts/demo-ci-cd.sh --fast

# Run specific test suite
./scripts/demo-ci-cd.sh --test-suite local

# Keep containers running
./scripts/demo-ci-cd.sh --no-cleanup
```

## Pipeline Stages Explained

### Stage 1: Checkout
- Verifies source code is available
- Shows git commit and branch information

### Stage 2: Prerequisites
- Checks Docker, Java, Gradle availability
- Verifies Docker daemon is running

### Stage 3: Build Docker Images
- Builds mock-confluent-api
- Builds metadata-service
- Builds stream-processor

### Stage 4: Start Test Infrastructure
- Starts Kafka (Confluent 7.5.0)
- Starts Schema Registry
- Starts Mock Confluent Flink API
- Initializes Kafka topics

### Stage 5: Start Services
- Starts Metadata Service
- Starts Stream Processor
- Waits for health checks

### Stage 6: Run Local Integration Tests
- LocalKafkaIntegrationTest
- FilterLifecycleLocalTest
- StreamProcessorLocalTest

### Stage 7: Run Schema Evolution Tests
- NonBreakingSchemaTest

### Stage 8: Run Breaking Schema Tests
- Starts V2 system (parallel deployment)
- BreakingSchemaChangeTest

### Stage 9: Generate Test Reports
- Generates JUnit XML reports
- Generates HTML test reports

## Demo Scenarios

### Scenario 1: Full Pipeline Demo

```bash
./scripts/demo-ci-cd.sh
```

Runs complete pipeline with all test suites.

### Scenario 2: Fast Iteration Demo

```bash
./scripts/demo-ci-cd.sh --fast --test-suite local
```

Skips Docker builds and runs only local tests for faster iteration.

### Scenario 3: Schema Change Demo

```bash
./scripts/demo-ci-cd.sh --test-suite schema
```

Demonstrates schema evolution testing.

### Scenario 4: Breaking Change Demo

```bash
./scripts/demo-ci-cd.sh --test-suite breaking
```

Demonstrates V2 parallel deployment for breaking schema changes.

### Scenario 5: Stage-by-Stage Demo

```bash
# Build images
./scripts/jenkins-local-simulate.sh --stage build

# Start infrastructure
./scripts/jenkins-local-simulate.sh --stage infrastructure

# Start services
./scripts/jenkins-local-simulate.sh --stage services

# Run tests
./scripts/jenkins-local-simulate.sh --stage test-local
```

Run stages individually for detailed inspection.

## Test Reports

After running tests, view reports:

**HTML Report:**
```bash
open cdc-streaming/e2e-tests/build/reports/tests/test/index.html
```

**JUnit XML Reports:**
```bash
ls -la cdc-streaming/e2e-tests/build/test-results/test/
```

## Environment Variables

The simulation respects these environment variables (matching Jenkins):

- `BUILD_NUMBER` - Build number (defaults to timestamp)
- `WORKSPACE` - Workspace directory (defaults to project root)
- `JAVA_HOME` - Java installation path

## Comparison with Real Jenkins

| Feature | Local Simulation | Real Jenkins |
|---------|------------------|--------------|
| Pipeline stages | ✅ Simulated | ✅ Native |
| Docker builds | ✅ Yes | ✅ Yes |
| Test execution | ✅ Yes | ✅ Yes |
| Test reports | ✅ HTML + JUnit | ✅ HTML + JUnit |
| Email notifications | ❌ No | ✅ Yes |
| Build history | ❌ No | ✅ Yes |
| Artifact archiving | ❌ No | ✅ Yes |
| Parallel execution | ❌ No | ✅ Yes |
| Build parameters | ✅ CLI args | ✅ UI |

## Troubleshooting

### Docker Not Running

```bash
# Check Docker status
docker ps

# Start Docker Desktop
open -a Docker
```

### Port Conflicts

```bash
# Check what's using ports
lsof -i :8080
lsof -i :9092

# Kill processes or change ports in docker-compose.integration-test.yml
```

### Services Not Starting

```bash
# Check logs
docker-compose -f docker-compose.integration-test.yml logs kafka
docker-compose -f docker-compose.integration-test.yml logs metadata-service

# Restart services
docker-compose -f docker-compose.integration-test.yml restart
```

### Test Failures

1. Check test reports: `cdc-streaming/e2e-tests/build/reports/tests/test/index.html`
2. Verify services are healthy:
   ```bash
   curl http://localhost:8080/api/v1/health
   curl http://localhost:8083/actuator/health
   ```
3. Check Docker logs for errors

## Next Steps

After local demo works:

1. **Deploy to Jenkins**: Use `Jenkinsfile` or `Jenkinsfile.groovy` in your Jenkins server
2. **Configure webhooks**: Set up Git webhooks to trigger builds automatically
3. **Add notifications**: Configure email/Slack notifications in Jenkins
4. **Set up build history**: Configure retention policies in Jenkins

## Example Demo Flow

```bash
# 1. Setup check
./scripts/setup-jenkins-local.sh

# 2. Full pipeline demo
./scripts/demo-ci-cd.sh

# 3. View results
open cdc-streaming/e2e-tests/build/reports/tests/test/index.html

# 4. Cleanup (if needed)
docker-compose -f docker-compose.integration-test.yml down
```

