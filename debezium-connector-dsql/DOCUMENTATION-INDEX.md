# Documentation Index - DSQL Debezium Connector

This document provides an index of all documentation files in the connector folder, organized by purpose.

## 🎯 Production & Deployment

### Current Production Setup
- **[PRODUCTION-SETUP.md](PRODUCTION-SETUP.md)** ⭐ **START HERE**
  - Complete production deployment documentation
  - Architecture diagram
  - Current configuration
  - Monitoring procedures
  - Troubleshooting guide
  - Last updated: December 19, 2025

### Deployment Guides
- **[QUICK-START.md](QUICK-START.md)** - Step-by-step quick deployment guide
- **[KAFKA-CONNECT-DEPLOYMENT.md](KAFKA-CONNECT-DEPLOYMENT.md)** - Detailed Kafka Connect deployment
- **[DEPLOYMENT-COMPLETE.md](DEPLOYMENT-COMPLETE.md)** - Deployment completion summary
- **[DEPLOYMENT-READY.md](DEPLOYMENT-READY.md)** - Pre-deployment checklist
- **[DEPLOYMENT-STATUS.md](DEPLOYMENT-STATUS.md)** - Deployment status tracking
- **[README-BASTION-DEPLOYMENT.md](README-BASTION-DEPLOYMENT.md)** - Bastion deployment summary

## 🧪 Testing

- **[TESTING.md](TESTING.md)** - General testing guide (unit, integration, Testcontainers)
- **[TESTING-REAL-DSQL.md](TESTING-REAL-DSQL.md)** - Testing with real DSQL cluster
- **[BASTION-TESTING-GUIDE.md](BASTION-TESTING-GUIDE.md)** - Testing on bastion host
- **[debezium-test-scenarios.md](debezium-test-scenarios.md)** - Test scenarios reference

## 🏗️ Infrastructure Setup

- **[BASTION-DOCKER-SETUP.md](BASTION-DOCKER-SETUP.md)** - Docker installation on bastion
- **[BASTION-SETUP-STATUS.md](BASTION-SETUP-STATUS.md)** - Infrastructure setup status
- **[BASTION-INFO.txt](BASTION-INFO.txt)** - Quick bastion reference
- **[test-on-ec2-md](test-on-ec2-md)** - Original EC2/Docker setup instructions

## 📋 Reference

- **[README.md](README.md)** - Main connector documentation
  - Overview and architecture
  - Configuration reference
  - Building and deployment options
  - IAM authentication setup
  - Change detection strategy
  - Multi-region failover
  - Monitoring and troubleshooting

- **[NEXT-STEPS.md](NEXT-STEPS.md)** - Next steps guide
- **[SETUP-COMPLETE.txt](SETUP-COMPLETE.txt)** - Setup completion summary

## 🔧 Scripts Documentation

All scripts are in `scripts/` directory:

| Script | Purpose | Documentation |
|--------|---------|---------------|
| `monitor-pipeline.sh` | Monitor entire CDC pipeline | See PRODUCTION-SETUP.md |
| `setup-from-terraform.sh` | Extract config from Terraform | See QUICK-START.md |
| `deploy-kafka-connect-bastion.sh` | Deploy Kafka Connect | See KAFKA-CONNECT-DEPLOYMENT.md |
| `create-connector-bastion.sh` | Create connector | See QUICK-START.md |
| `verify-bastion-setup.sh` | Verify infrastructure | See BASTION-SETUP-STATUS.md |
| `upload-to-bastion.sh` | Upload files to bastion | See BASTION-TESTING-GUIDE.md |
| `test-real-dsql.sh` | Run real DSQL tests | See TESTING-REAL-DSQL.md |
| `validate-dsql-connection.sh` | Validate connection | See TESTING-REAL-DSQL.md |

## 📊 Quick Reference

### For New Users
1. Start with **[PRODUCTION-SETUP.md](PRODUCTION-SETUP.md)** to understand current setup
2. Review **[README.md](README.md)** for connector overview
3. Use **[QUICK-START.md](QUICK-START.md)** for deployment

### For Deployment
1. **[QUICK-START.md](QUICK-START.md)** - Quick deployment
2. **[KAFKA-CONNECT-DEPLOYMENT.md](KAFKA-CONNECT-DEPLOYMENT.md)** - Detailed deployment
3. **[PRODUCTION-SETUP.md](PRODUCTION-SETUP.md)** - Production configuration

### For Monitoring
1. **[PRODUCTION-SETUP.md](PRODUCTION-SETUP.md)** - Monitoring section
2. Run `./scripts/monitor-pipeline.sh` for real-time status

### For Troubleshooting
1. **[PRODUCTION-SETUP.md](PRODUCTION-SETUP.md)** - Troubleshooting section
2. **[README.md](README.md)** - Common issues
3. Check logs: `docker logs dsql-kafka-connect`

## 📝 Documentation Updates

**Last Major Update**: December 19, 2025
- Created PRODUCTION-SETUP.md with complete current deployment details
- Added monitoring script
- Updated README.md with documentation index
- Verified all configuration files and scripts

## 🔗 External Resources

- [Debezium Documentation](https://debezium.io/documentation/)
- [Kafka Connect REST API](https://kafka.apache.org/documentation/#connect_rest)
- [Amazon Aurora DSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html)
- [Confluent Cloud](https://docs.confluent.io/cloud/current/overview.html)
