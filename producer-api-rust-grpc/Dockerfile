# Build stage
FROM rust:1.88 as builder

# Install protoc for building proto files
RUN apt-get update && \
    apt-get install -y protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency files
COPY Cargo.toml ./
COPY proto ./proto
COPY build.rs ./
COPY migrations ./migrations

# Create a dummy src to build dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy actual source code
COPY src ./src

# Build the application
RUN touch src/main.rs && \
    cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/producer-api-rust-grpc /app/producer-api-rust-grpc

# Expose port
EXPOSE 9090

# Run the application
CMD ["./producer-api-rust-grpc"]
