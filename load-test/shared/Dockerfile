FROM grafana/k6:latest

# Switch to root to install packages
USER root

# Install additional tools for health checks and utilities
RUN apk add --no-cache \
    bash \
    curl \
    netcat-openbsd \
    python3 \
    py3-pip \
    postgresql-dev \
    gcc \
    musl-dev \
    && rm -rf /var/cache/apk/*

# Install Python dependencies
# Use --break-system-packages flag for Alpine Linux Python PEP 668 protection
RUN pip3 install --no-cache-dir --break-system-packages psycopg2-binary

# Create directories for test scripts and results
RUN mkdir -p /k6/scripts /k6/results /k6/proto

# Switch back to k6 user (non-root)
USER k6

# Set working directory
WORKDIR /k6

# Default command - will be overridden by docker-compose run
CMD ["/bin/sh", "-c", "echo 'k6 container ready. Use docker-compose run to execute tests.'"]
