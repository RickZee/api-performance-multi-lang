#!/usr/bin/env python3
"""
Service Consumer for MSK
Consumes filtered service events from MSK topic: filtered-service-events-msk
"""

import os
import json
import logging
import sys
from datetime import datetime
from confluent_kafka import Consumer, KafkaError
from aws_msk_iam_sasl_signer_python import MSKAuthTokenProvider

try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger('service-consumer-msk')

KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', '')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'filtered-service-events-msk')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'service-consumer-group-msk')
KAFKA_CLIENT_ID = os.getenv('KAFKA_CLIENT_ID', CONSUMER_GROUP_ID.replace('-group', '-client'))

def format_timestamp(utc_timestamp_str):
    if not utc_timestamp_str or utc_timestamp_str == 'Unknown':
        return utc_timestamp_str
    try:
        if utc_timestamp_str.endswith('Z'):
            dt_utc = datetime.fromisoformat(utc_timestamp_str.replace('Z', '+00:00'))
        else:
            dt_utc = datetime.fromisoformat(utc_timestamp_str)
            if dt_utc.tzinfo is None:
                dt_utc = dt_utc.replace(tzinfo=ZoneInfo('UTC'))
        return utc_timestamp_str
    except Exception as e:
        logger.warning(f"Failed to parse timestamp: {e}")
        return utc_timestamp_str

def process_event(event_value):
    try:
        event_id = event_value.get('id', 'Unknown')
        event_type = event_value.get('event_type', 'Unknown')
        created_date = event_value.get('created_date', 'Unknown')
        
        logger.info("=" * 80)
        logger.info(f"Service Event Received (MSK)")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {format_timestamp(created_date)}")
        logger.info("=" * 80)
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    logger.info("Starting Service Consumer (MSK)...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    
    if not KAFKA_BOOTSTRAP_SERVERS:
        logger.error("KAFKA_BOOTSTRAP_SERVERS environment variable is required")
        sys.exit(1)
    
    token_provider = MSKAuthTokenProvider(region=AWS_REGION)
    
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'client.id': KAFKA_CLIENT_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'security.protocol': 'SASL_SSL',
        'sasl.mechanism': 'AWS_MSK_IAM',
        'sasl.aws.msk.iam.token.provider': token_provider,
    }
    
    consumer = Consumer(consumer_config)
    consumer.subscribe([KAFKA_TOPIC])
    logger.info("Consumer started. Waiting for messages...")
    
    try:
        while True:
            msg = consumer.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                if msg.error().code() != KafkaError._PARTITION_EOF:
                    logger.error(f"Consumer error: {msg.error()}")
                continue
            try:
                event_value = json.loads(msg.value().decode('utf-8'))
                process_event(event_value)
            except Exception as e:
                logger.error(f"Error processing message: {e}", exc_info=True)
    except KeyboardInterrupt:
        logger.info("Shutting down consumer...")
    finally:
        consumer.close()

if __name__ == '__main__':
    main()

