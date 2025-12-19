# Testing Guide for DSQL Debezium Connector

## Running Tests

### Prerequisites
- Docker must be running
- Java 11+
- Gradle

### Running All Tests

```bash
./gradlew test
```

### Running Tests with Docker

On macOS, Docker Desktop uses a custom socket location. To run integration tests that require Docker, use one of the following options:

#### Option 1: Enable Default Docker Socket (Recommended for macOS)

This is the easiest and most reliable option:

1. Open Docker Desktop
2. Go to **Settings** → **Advanced**
3. Enable **"Enable default Docker socket"**
4. Click **"Apply & Restart"**

This creates `/var/run/docker.sock` automatically, and Testcontainers will detect Docker without any additional configuration.

#### Option 2: Use Setup Script

Run the setup script to automatically configure Testcontainers:

```bash
./setup-testcontainers.sh
```

This script will:
- Detect your Docker socket location
- Create/update `~/.testcontainers.properties` with the correct configuration
- Provide instructions if Docker is not found

#### Option 3: Use Helper Script

Use the provided script that sets DOCKER_HOST automatically:

```bash
./run-tests-with-docker.sh
```

This script detects Docker socket location and sets DOCKER_HOST before running tests.

#### Option 4: Set DOCKER_HOST Environment Variable

Manually set the DOCKER_HOST environment variable:

```bash
# For current session
export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock
./gradlew test

# For permanent setup (add to ~/.zshrc or ~/.bashrc)
echo 'export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock' >> ~/.zshrc
```

#### Option 5: Configure ~/.testcontainers.properties

Create or edit `~/.testcontainers.properties` in your home directory:

```properties
docker.host=unix:///Users/YOUR_USERNAME/.docker/run/docker.sock
```

Replace `YOUR_USERNAME` with your actual username.

### Test Categories

- **Unit Tests**: Run without Docker (all passing)
- **Integration Tests**: Require Docker/Testcontainers (will be skipped if Docker not detected)
- **Performance Tests**: Tagged with `@Tag("slow")` - can be excluded with `--exclude-tag slow`

### Running Specific Test Classes

```bash
./gradlew test --tests "DsqlDataTypeMappingTest"
./gradlew test --tests "DsqlConnectorIT"
```

### Test Results

Test reports are generated at: `build/reports/tests/test/index.html`

## Test Coverage

The test suite includes:

1. **Unit Tests** (100+ tests)
   - Schema building and validation
   - Offset management
   - Configuration validation
   - Error recovery
   - Connection pooling
   - Multi-region endpoint management

2. **Integration Tests** (80+ tests)
   - Data type mapping edge cases
   - Transaction and size limits
   - Streaming scenarios
   - Resource limits
   - Load testing
   - Multi-region replication

3. **Structural Tests** (for future features)
   - Incremental snapshots
   - OCC conflict handling
   - Heartbeat mechanism

## Troubleshooting

### Tests Skipped Due to Docker

If integration tests are being skipped, follow these steps:

1. **Verify Docker is running**:
   ```bash
   docker ps
   ```

2. **Check Docker socket location**:
   ```bash
   # Check default socket (if Docker Desktop default socket is enabled)
   ls -la /var/run/docker.sock
   
   # Check macOS Docker Desktop socket
   ls -la ~/.docker/run/docker.sock
   ```

3. **Check Docker availability programmatically**:
   The `DockerAvailability` utility class can help diagnose issues:
   ```java
   import io.debezium.connector.dsql.testutil.DockerAvailability;
   
   // Check if Docker is available
   boolean available = DockerAvailability.isDockerAvailable();
   
   // Get detailed status message
   String status = DockerAvailability.getDockerStatus();
   ```

4. **Recommended solution**: Enable "Enable default Docker socket" in Docker Desktop settings (see Option 1 above)

### Common Issues

#### Issue: "Could not find a valid Docker environment"

**Solution**: This means Testcontainers cannot detect Docker. Try:
1. Enable "Enable default Docker socket" in Docker Desktop (recommended)
2. Run `./setup-testcontainers.sh` to configure automatically
3. Set `DOCKER_HOST` environment variable manually

#### Issue: Tests skip even though Docker is running

**Solution**: Testcontainers checks Docker availability at initialization. Ensure:
1. Docker Desktop is fully started (not just installed)
2. Docker socket is accessible
3. DOCKER_HOST is set before running tests (use `./run-tests-with-docker.sh`)

#### Issue: Permission denied on Docker socket

**Solution**: Ensure your user has access to the Docker socket:
```bash
# Check socket permissions
ls -la /var/run/docker.sock
# or
ls -la ~/.docker/run/docker.sock

# If needed, add your user to docker group (Linux) or ensure proper permissions (macOS)
```

### Testcontainers Configuration

Testcontainers configuration can be set in multiple places (priority order):

1. **Environment variable**: `DOCKER_HOST` (highest priority)
2. **User properties file**: `~/.testcontainers.properties`
3. **Classpath properties file**: `src/test/resources/testcontainers.properties`
4. **Auto-detection**: Testcontainers tries to detect Docker automatically (lowest priority)

**Note**: Some Testcontainers settings (like `testcontainers.reuse.enable`) must be in `~/.testcontainers.properties`, not in the classpath file.

### Verifying Configuration

To verify your Docker configuration is working:

```bash
# Check if Docker is accessible
docker ps

# Check DOCKER_HOST environment variable
echo $DOCKER_HOST

# Check Testcontainers properties
cat ~/.testcontainers.properties 2>/dev/null || echo "No user-level properties file"

# Run a simple test to verify
./gradlew test --tests "DsqlDataTypeMappingTest.testDecimalPrecisionMapping"
```

If the test passes (not skipped), Docker is properly configured!
