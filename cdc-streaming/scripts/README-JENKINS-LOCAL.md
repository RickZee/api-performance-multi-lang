# Local Jenkins CI/CD Simulation - Quick Reference

## Quick Start

```bash
# 1. Check prerequisites
./scripts/setup-jenkins-local.sh

# 2. Run complete CI/CD demo
./scripts/demo-ci-cd.sh
```

## Common Commands

### Full Pipeline
```bash
./scripts/jenkins-local-simulate.sh
```

### Fast Demo (Skip Builds)
```bash
./scripts/demo-ci-cd.sh --fast
```

### Run Specific Test Suite
```bash
# Local tests only
./scripts/jenkins-local-simulate.sh --test-suite local

# Schema tests only
./scripts/jenkins-local-simulate.sh --test-suite schema

# Breaking change tests only
./scripts/jenkins-local-simulate.sh --test-suite breaking
```

### Run Specific Stage
```bash
./scripts/jenkins-local-simulate.sh --stage build
./scripts/jenkins-local-simulate.sh --stage test-local
./scripts/jenkins-local-simulate.sh --stage reports
```

### Keep Containers Running
```bash
./scripts/jenkins-local-simulate.sh --no-cleanup
```

## View Test Reports

```bash
open cdc-streaming/e2e-tests/build/reports/tests/test/index.html
```

## Cleanup

```bash
cd cdc-streaming
docker-compose -f docker-compose.integration-test.yml down
docker-compose -f docker-compose.integration-test.yml --profile v2 down
```

## Available Stages

- `checkout` - Verify source code
- `prerequisites` - Check tools
- `build` - Build Docker images
- `infrastructure` - Start Kafka/Registry
- `services` - Start Metadata/Stream Processor
- `test-local` - Run local integration tests
- `test-schema` - Run schema evolution tests
- `test-breaking` - Run breaking schema tests
- `reports` - Generate test reports

## Troubleshooting

**Docker not running:**
```bash
docker ps  # Should show running containers
```

**Port conflicts:**
```bash
lsof -i :8080  # Check what's using ports
```

**Services not healthy:**
```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8083/actuator/health
```

For detailed documentation, see: `JENKINS_LOCAL_DEMO.md`

