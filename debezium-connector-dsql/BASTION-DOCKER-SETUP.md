# Installing Docker on Bastion Host

This guide provides instructions for installing Docker Engine on the bastion host to enable containerized testing and deployment.

## Bastion Host Information

From Terraform outputs:

- **Instance ID**: `i-0adcbf0f85849149e`
- **Public IP**: `44.198.171.47`
- **Region**: `us-east-1`
- **SSM Command**: `aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1`

## Quick Start

### Option 1: Automated Installation (Recommended)

1. **Connect to bastion via SSM**:
   ```bash
   aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1
   ```

2. **Upload and run the installation script**:
   ```bash
   # On your local machine, upload the script
   aws ssm send-command \
     --instance-ids i-0adcbf0f85849149e \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["curl -o /tmp/install-docker.sh https://raw.githubusercontent.com/.../install-docker-bastion-commands.sh","bash /tmp/install-docker.sh"]' \
     --region us-east-1
   ```

   Or manually:
   ```bash
   # Copy script to bastion (from local machine)
   scp scripts/install-docker-bastion-commands.sh ec2-user@44.198.171.47:/tmp/
   
   # Then on bastion
   chmod +x /tmp/install-docker-bastion-commands.sh
   /tmp/install-docker-bastion-commands.sh
   ```

### Option 2: Manual Installation

1. **Connect to bastion**:
   ```bash
   aws ssm start-session --target i-0adcbf0f85849149e --region us-east-1
   ```

2. **Run installation commands**:
   ```bash
   # Update system
   sudo dnf update -y
   
   # Install Docker
   sudo yum install -y docker
   
   # Start and enable Docker
   sudo systemctl start docker
   sudo systemctl enable docker
   sudo systemctl status docker
   
   # Add user to docker group
   sudo usermod -aG docker ec2-user
   newgrp docker  # Apply in current session
   
   # Test Docker
   docker version
   docker run --rm hello-world
   ```

3. **Log out and reconnect** for group changes to take full effect.

## Verification

After installation and reconnection, verify Docker works:

```bash
# Should work without sudo
docker version

# Test container
docker run --rm hello-world

# Check Docker info
docker info
```

## Optional: Docker Compose Plugin

For multi-container setups (e.g., Kafka Connect + Zookeeper):

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

## Next Steps

After Docker is installed:

1. **Test connector on bastion**: Upload connector JAR and run tests
2. **Deploy Kafka Connect**: Run Kafka Connect in a container
3. **Run integration tests**: Execute real DSQL tests from bastion
4. **Secure tunneling**: Use Docker for secure database access

## Troubleshooting

### Docker service won't start

```bash
# Check logs
sudo journalctl -u docker -n 50

# Check status
sudo systemctl status docker
```

### Permission denied errors

```bash
# Verify user is in docker group
groups

# If not, add and reconnect
sudo usermod -aG docker ec2-user
# Log out and back in
```

### Cannot connect to Docker daemon

- Ensure Docker service is running: `sudo systemctl status docker`
- Verify group membership: `groups | grep docker`
- Try with `newgrp docker` or reconnect

## Security Notes

- Docker socket is secured via group membership (not chmod 666)
- Security group restricts outbound access
- Use IAM roles for AWS resource access
- Monitor Docker activity via CloudWatch/ELK
