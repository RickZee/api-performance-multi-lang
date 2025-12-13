.PHONY: test test-integration test-unit build run clean

# Run all tests
test: test-unit test-integration

# Run unit tests only
test-unit:
	go test -v -short ./...

# Run integration tests (requires git)
test-integration:
	go test -v -run TestIntegration ./...

# Run specific integration test
test-integration-git:
	go test -v -run TestGitSync ./...

test-integration-api:
	go test -v -run TestValidate ./...

test-integration-compat:
	go test -v -run TestCompatibility ./...

# Build the service
build:
	go build -o bin/metadata-service ./cmd/server

# Run the service locally
run:
	go run ./cmd/server/main.go

# Clean build artifacts
clean:
	rm -rf bin/
	go clean

# Install dependencies
deps:
	go mod download
	go mod tidy

# Run with race detector
test-race:
	go test -race ./...

# Run with coverage
test-coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

