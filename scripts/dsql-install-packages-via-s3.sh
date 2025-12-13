#!/bin/bash
# Install packages on EC2 via S3 (no NAT needed)
# Upload this script to S3, then download and run on EC2

set -e

echo "=== Installing packages via S3 ==="

# Download packages from S3 (pre-uploaded) or use local package cache
# For now, try IPv6 connectivity first
if ping6 -c 1 2001:4860:4860::8888 > /dev/null 2>&1; then
    echo "IPv6 connectivity working, installing via dnf..."
    sudo dnf install -y postgresql16 || sudo dnf install -y postgresql15 || sudo dnf install -y postgresql
else
    echo "IPv6 not working, will need to use alternative method"
fi

# Install k6 from GitHub releases (supports IPv6)
curl -L https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz | tar xz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
k6 version

echo "=== Package installation complete ==="
