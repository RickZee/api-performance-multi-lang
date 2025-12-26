#!/usr/bin/env python3
"""
Script to create MSK topic using AWS MSK IAM authentication.
Requires: pip install kafka-python boto3
"""

import sys
import os
from kafka import KafkaAdminClient
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError
import boto3
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

def create_topic(bootstrap_servers, topic_name, partitions=3, replication_factor=1):
    """Create a Kafka topic using IAM authentication."""
    
    # Get AWS credentials
    session = boto3.Session()
    credentials = session.get_credentials()
    
    # Create MSK IAM auth provider
    auth_provider = MSKAuthTokenProvider(
        region=session.region_name or 'us-east-1'
    )
    
    # Create admin client with IAM auth
    admin_client = KafkaAdminClient(
        bootstrap_servers=bootstrap_servers,
        security_protocol='SASL_SSL',
        sasl_mechanism='AWS_MSK_IAM',
        sasl_oauth_token_provider=auth_provider,
        api_version=(2, 6, 0)
    )
    
    # Create topic
    topic = NewTopic(
        name=topic_name,
        num_partitions=partitions,
        replication_factor=replication_factor
    )
    
    try:
        admin_client.create_topics([topic])
        print(f"✅ Topic '{topic_name}' created successfully")
        return True
    except TopicAlreadyExistsError:
        print(f"ℹ️  Topic '{topic_name}' already exists")
        return True
    except Exception as e:
        print(f"❌ Error creating topic: {e}")
        return False
    finally:
        admin_client.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 create-msk-topic.py <bootstrap-servers> <topic-name> [partitions]")
        print("Example: python3 create-msk-topic.py boot-xxx.c1.kafka-serverless.us-east-1.amazonaws.com:9098 raw-event-headers 3")
        sys.exit(1)
    
    bootstrap_servers = sys.argv[1]
    topic_name = sys.argv[2]
    partitions = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    
    success = create_topic(bootstrap_servers, topic_name, partitions)
    sys.exit(0 if success else 1)

