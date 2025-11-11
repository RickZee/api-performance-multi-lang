# Build stage
FROM golang:1.21-alpine AS builder

# Install protoc, bash, and dependencies
RUN apk add --no-cache protobuf protobuf-dev bash

WORKDIR /app

# Copy go mod files
COPY go.mod ./
RUN go mod download

# Copy source code
COPY . .

# Generate proto files
RUN chmod +x scripts/generate-proto.sh && \
    bash scripts/generate-proto.sh

# Generate go.sum by getting all dependencies
RUN go get ./... || true

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o producer-api-go-grpc ./cmd/server

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the binary from builder
COPY --from=builder /app/producer-api-go-grpc .
COPY --from=builder /app/migrations ./migrations

# Expose port
EXPOSE 7090

# Run the binary
CMD ["./producer-api-go-grpc"]

