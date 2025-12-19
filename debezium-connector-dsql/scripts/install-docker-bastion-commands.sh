#!/bin/bash
# Commands to run ON the bastion host to install Docker
# This script should be executed after connecting to the bastion via SSM or SSH

set -e

echo "=========================================="
echo "Installing Docker Engine on Bastion Host"
echo "=========================================="
echo ""

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Detected OS: $ID $VERSION_ID"
else
    echo "Warning: Could not detect OS version"
fi

echo ""

# Step 1: Update system packages
echo "Step 1: Updating system packages..."
if command -v dnf &> /dev/null; then
    sudo dnf update -y
elif command -v yum &> /dev/null; then
    sudo yum update -y
else
    echo "Error: Neither dnf nor yum found"
    exit 1
fi

echo "✓ System packages updated"
echo ""

# Step 2: Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "⚠ Docker is already installed"
    echo "Current version:"
    docker --version
    echo ""
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping Docker installation"
        exit 0
    fi
    echo "Uninstalling existing Docker..."
    sudo dnf remove -y docker* 2>/dev/null || sudo yum remove -y docker* 2>/dev/null || true
fi

# Step 3: Install Docker Engine
echo "Step 2: Installing Docker Engine..."
if command -v dnf &> /dev/null; then
    sudo dnf install -y docker
elif command -v yum &> /dev/null; then
    sudo yum install -y docker
fi

echo "✓ Docker Engine installed"
echo ""

# Step 4: Start and enable Docker service
echo "Step 3: Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

echo "Checking Docker status..."
if sudo systemctl is-active --quiet docker; then
    echo "✓ Docker service is running"
else
    echo "✗ Error: Docker service failed to start"
    sudo systemctl status docker
    exit 1
fi

echo ""

# Step 5: Add user to docker group
echo "Step 4: Adding ec2-user to docker group..."
sudo usermod -aG docker ec2-user

echo "✓ User added to docker group"
echo ""
echo "⚠ Important: You need to log out and reconnect for group changes to take effect"
echo "   Or run: newgrp docker (in current session)"
echo ""

# Step 6: Test Docker (with sudo for now, since group change needs reconnection)
echo "Step 5: Testing Docker installation..."
sudo docker version
echo ""

# Step 7: Run hello-world test
echo "Step 6: Running Docker hello-world test..."
sudo docker run --rm hello-world
echo ""

# Step 8: Optional - Install Docker Compose Plugin
echo "Step 7: Installing Docker Compose Plugin (optional)..."
read -p "Install Docker Compose Plugin? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    if sudo docker compose version &>/dev/null; then
        echo "✓ Docker Compose Plugin installed"
        sudo docker compose version
    else
        echo "⚠ Docker Compose Plugin installation may have failed"
    fi
else
    echo "Skipping Docker Compose Plugin installation"
fi

echo ""
echo "=========================================="
echo "Docker Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Log out and reconnect (or run: newgrp docker)"
echo "2. Test without sudo: docker version"
echo "3. Verify: docker run --rm hello-world"
echo ""
echo "Docker is now ready for:"
echo "  - Kafka Connect containerized deployment"
echo "  - Integration test execution"
echo "  - Secure database tunneling"
echo ""
