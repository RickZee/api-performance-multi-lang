# Jenkins CI/CD Setup for Integration Tests

This document describes how to set up and run the integration test suite using Jenkins.

## Prerequisites

### Jenkins Agent Requirements

- **Docker** installed and running
- **Docker Compose** (v2 `docker compose` or v1 `docker-compose`)
- **Java 17+** (JDK)
- **Gradle** (will be downloaded by wrapper)
- **Network access** to pull Docker images

### Jenkins Plugins Required

- **Pipeline** plugin
- **Docker Pipeline** plugin
- **JUnit** plugin (for test results)
- **HTML Publisher** plugin (for test reports)
- **Email Extension** plugin (optional, for notifications)
- **AnsiColor** plugin (optional, for colored output)
- **Timestamper** plugin (optional, for timestamps)

## Jenkinsfile Configuration

Two Jenkinsfile options are provided:

1. **`Jenkinsfile`** - Basic declarative pipeline
2. **`Jenkinsfile.groovy`** - Advanced pipeline with parameters and email notifications

### Using the Basic Pipeline

```groovy
// In Jenkins, create a new Pipeline job and point to Jenkinsfile
```

### Using the Advanced Pipeline

The `Jenkinsfile.groovy` includes:

- **Build parameters**:
  - `TEST_SUITE`: Choose which tests to run (all, local, schema, breaking)
  - `SKIP_BUILD`: Skip Docker image builds
  - `CLEANUP`: Clean up containers after tests

- **Email notifications** on success/failure
- **Test result publishing** with HTML reports
- **Artifact archiving**

## Jenkins Job Configuration

### Create Pipeline Job

1. **New Item** → **Pipeline**
2. **Pipeline Definition**: 
   - Select "Pipeline script from SCM"
   - SCM: Git
   - Repository URL: Your repository URL
   - Branch: `*/cicd-int-test-filtering` or `*/main`
   - Script Path: `Jenkinsfile` or `Jenkinsfile.groovy`

### Configure JDK Tool

1. **Manage Jenkins** → **Global Tool Configuration**
2. Add JDK installation:
   - Name: `JDK-17`
   - JAVA_HOME: Path to JDK 17 installation

### Configure Docker

Ensure Jenkins agent has Docker access:

```bash
# On Jenkins agent
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

## Pipeline Stages

The pipeline executes the following stages:

1. **Checkout** - Get source code
2. **Prerequisites** - Verify tools are available
3. **Build Docker Images** - Build test infrastructure images
4. **Start Test Infrastructure** - Start Kafka, Schema Registry, Mock API
5. **Start Services** - Start Metadata Service and Stream Processor
6. **Run Local Integration Tests** - Execute local test suite
7. **Run Schema Evolution Tests** - Execute non-breaking schema tests
8. **Run Breaking Schema Tests (V2)** - Execute V2 parallel deployment tests
9. **Generate Test Reports** - Create HTML and JUnit reports

## Test Execution

### Running All Tests

Default behavior runs all test suites:

```bash
# Triggered via Jenkins UI or webhook
```

### Running Specific Test Suites

If using `Jenkinsfile.groovy` with parameters:

- **all**: Run all tests (default)
- **local**: Run only local integration tests
- **schema**: Run only schema evolution tests
- **breaking**: Run only breaking schema change tests

## Test Reports

Test results are published in multiple formats:

1. **JUnit XML**: `cdc-streaming/e2e-tests/build/test-results/test/*.xml`
2. **HTML Reports**: `cdc-streaming/e2e-tests/build/reports/tests/test/index.html`
3. **Console Output**: Full build logs in Jenkins

## Manual Test Execution

To run tests manually on Jenkins agent:

```bash
cd /path/to/workspace
./cdc-streaming/scripts/run-all-integration-tests.sh
```

Or use individual scripts:

```bash
# Local integration tests
./cdc-streaming/scripts/run-local-integration-tests.sh

# Schema evolution tests
./cdc-streaming/scripts/run-schema-evolution-tests.sh

# With V2 system
./cdc-streaming/scripts/run-local-integration-tests.sh --profile v2
```

## Troubleshooting

### Docker Permission Issues

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Port Conflicts

If ports 8080, 8081, 8082, 8083, 9092 are in use:

```bash
# Check what's using the ports
sudo lsof -i :8080
sudo lsof -i :9092

# Kill processes or change ports in docker-compose.integration-test.yml
```

### Services Not Starting

Check Docker logs:

```bash
docker-compose -f cdc-streaming/docker-compose.integration-test.yml logs kafka
docker-compose -f cdc-streaming/docker-compose.integration-test.yml logs metadata-service
```

### Test Failures

1. Check test reports in Jenkins
2. Review console output for errors
3. Verify services are healthy:
   ```bash
   curl http://localhost:8080/api/v1/health
   curl http://localhost:8083/actuator/health
   ```

## Continuous Integration Triggers

### Poll SCM

Configure in Jenkins job:

```
# Poll every 5 minutes
H/5 * * * *
```

### Webhook Triggers

For GitHub/GitLab webhooks:

1. Install **GitHub Plugin** or **GitLab Plugin**
2. Configure webhook in repository settings
3. Add webhook URL: `http://jenkins-server/github-webhook/`

### Branch Strategy

- **Main branch**: Run all tests including V2 breaking schema tests
- **Feature branches**: Run local and schema tests only
- **PR validation**: Run all tests before merge

## Best Practices

1. **Use Docker agents** for isolation
2. **Clean up containers** after tests (enabled by default)
3. **Archive test reports** for historical analysis
4. **Set timeouts** to prevent hanging builds
5. **Use build parameters** for flexible test execution
6. **Monitor resource usage** (CPU, memory, disk)

## Example Jenkins Job Configuration

```groovy
pipeline {
    agent { label 'docker' }
    
    triggers {
        pollSCM('H/5 * * * *')  // Poll every 5 minutes
        githubPush()  // Trigger on GitHub push
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    // ... rest of pipeline
}
```

