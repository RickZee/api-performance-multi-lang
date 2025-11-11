# Build stage
FROM rust:1.88 as builder

WORKDIR /app

# Copy dependency files
COPY Cargo.toml ./
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
COPY --from=builder /app/target/release/producer-api-rust /app/producer-api-rust

# Expose port
EXPOSE 8081

# Run the application
CMD ["./producer-api-rust"]

