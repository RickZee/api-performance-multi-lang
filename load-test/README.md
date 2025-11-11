# Producer API Performance Testing

This directory contains k6-based performance testing infrastructure for comparing the 6 producer API implementations.

## Overview

The performance testing framework uses **k6** - a modern, developer-friendly load testing tool - to determine the maximum sustainable throughput and optimal parallelism level for each producer API implementation.

## Key Features

- **Automatic Smoke Tests**: Smoke tests run automatically before full or saturation tests to verify basic functionality
- **Docker Execution**: k6 runs in Docker containers - no local installation required
- **Sequential Testing**: Tests run one API at a time for fair comparison
- **Database Clearing**: Database is automatically cleared between API tests
- **Validation**: Smoke test results are validated (error rate < 5%, success rate > 95%)
- **Native gRPC Support**: Built-in gRPC testing without plugins
- **Multiple Test Modes**: Smoke (quick validation), Full (up to 100 VUs), and Saturation (up to 2000 VUs) tests

## Directory Structure

```
load-test/
├── k6/                          # k6 test scripts
│   ├── rest-api-test.js        # REST API test script
│   ├── grpc-api-test.js        # gRPC API test script
│   ├── config.js               # k6 configuration
│   └── shared/
│       └── helpers.js          # Shared helper functions
├── shared/                      # Test execution scripts
│   ├── run-sequential-throughput-tests.sh   # Sequential throughput tests
│   ├── analyze-throughput-results.sh        # Results analysis
│   ├── extract_k6_metrics.py               # Metrics extraction
│   ├── color-output.sh                      # Colored output utilities
│   └── common-functions.sh                  # Common functions
├── results/                     # Test results directory
│   └── throughput-sequential/   # Sequential test results
├── README.md                    # This file
└── THROUGHPUT-TESTING-GUIDE.md  # Detailed testing guide
```

## Running Throughput Tests

### Sequential Tests (Recommended)

Sequential tests run one API at a time, ensuring fair comparison by clearing the database between tests:

```bash
cd load-test/shared

# Run full throughput tests (automatically runs smoke tests first)
./run-sequential-throughput-tests.sh full

# Run saturation tests to find maximum throughput (automatically runs smoke tests first)
./run-sequential-throughput-tests.sh saturation

# Run smoke tests only
./run-sequential-throughput-tests.sh smoke
```


## Test Workflow

1. **Smoke Tests** (automatic when running full or saturation tests):
   - 10 VUs (virtual users), 30 seconds
   - Validates basic functionality
   - Must pass before full or saturation tests proceed

2. **Full Tests**:
   - 4 phases: 10 → 50 → 100 → 200 VUs
   - ~11 minutes per API
   - Identifies optimal parallelism and breaking points

3. **Saturation Tests**:
   - 7 phases: 10 → 50 → 100 → 200 → 500 → 1000 → 2000 VUs
   - ~14 minutes per API
   - Finds absolute maximum throughput and true breaking points

## Test Results

Results are saved to:
- Sequential: `load-test/results/throughput-sequential/<api_name>/`

Each test generates:
- JSON result files (k6 metrics)
- Summary reports
- Comparison reports (for sequential tests)

## Producer API Implementations

The tests cover all 6 producer API implementations:

1. **producer-api-java-rest** - Spring Boot REST (port 9081, profile: `producer-java-rest`)
2. **producer-api-java-grpc** - Java gRPC (port 9090, profile: `producer-java-grpc`)
3. **producer-api-rust-rest** - Rust REST (port 9082, profile: `producer-rust-rest`)
4. **producer-api-rust-grpc** - Rust gRPC (port 9091, profile: `producer-rust-grpc`)
5. **producer-api-go-rest** - Go REST (port 9083, profile: `producer-go-rest`)
6. **producer-api-go-grpc** - Go gRPC (port 9092, profile: `producer-go-grpc`)

## Prerequisites

1. Docker and Docker Compose must be installed and running
2. All producer APIs use Docker Compose profiles and will be started automatically by the test scripts
3. PostgreSQL database must be accessible (will be started automatically for sequential tests)

**Note**: 
- k6 is executed in Docker containers - no local k6 installation required!
- The test scripts automatically start the required APIs using their profiles, so you don't need to manually start them
- All APIs use profiles (`producer-java-rest`, `producer-java-grpc`, `producer-rust-rest`, `producer-rust-grpc`, `producer-go-rest`, `producer-go-grpc`), so they won't start with a simple `docker-compose up`

## Detailed Documentation

For comprehensive information about the testing methodology, see [THROUGHPUT-TESTING-GUIDE.md](THROUGHPUT-TESTING-GUIDE.md).
