#!/usr/bin/env python3
"""
Loan Consumer for MSK
Consumes filtered loan created events from MSK topic: filtered-loan-created-events-msk
Connects to Amazon MSK with IAM authentication
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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger('loan-consumer-msk')

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', '')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'filtered-loan-created-events-msk')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'loan-consumer-group-msk')
KAFKA_CLIENT_ID = os.getenv('KAFKA_CLIENT_ID', CONSUMER_GROUP_ID.replace('-group', '-client'))
DISPLAY_TIMEZONE = os.getenv('DISPLAY_TIMEZONE', 'America/New_York')

def format_timestamp(utc_timestamp_str):
    """Convert UTC ISO 8601 timestamp to local time display format."""
    if not utc_timestamp_str or utc_timestamp_str == 'Unknown':
        return utc_timestamp_str
    
    try:
        if utc_timestamp_str.endswith('Z'):
            dt_utc = datetime.fromisoformat(utc_timestamp_str.replace('Z', '+00:00'))
        else:
            dt_utc = datetime.fromisoformat(utc_timestamp_str)
            if dt_utc.tzinfo is None:
                dt_utc = dt_utc.replace(tzinfo=ZoneInfo('UTC'))
        
        try:
            display_tz = ZoneInfo(DISPLAY_TIMEZONE)
            dt_local = dt_utc.astimezone(display_tz)
            tz_abbr = dt_local.strftime('%Z')
            local_str = dt_local.strftime('%Y-%m-%d %H:%M:%S')
            return f"{utc_timestamp_str} (Local: {local_str} {tz_abbr})"
        except Exception as e:
            logger.warning(f"Failed to convert to timezone {DISPLAY_TIMEZONE}: {e}")
            return utc_timestamp_str
    except Exception as e:
        logger.warning(f"Failed to parse timestamp '{utc_timestamp_str}': {e}")
        return utc_timestamp_str

def process_event(event_value):
    """Process a loan event"""
    try:
        event_id = event_value.get('id', 'Unknown')
        event_name = event_value.get('event_name', 'Unknown')
        event_type = event_value.get('event_type', 'Unknown')
        created_date = event_value.get('created_date', 'Unknown')
        saved_date = event_value.get('saved_date', 'Unknown')
        cdc_op = event_value.get('__op', 'Unknown')
        cdc_table = event_value.get('__table', 'Unknown')
        
        header_data_str = event_value.get('header_data', '{}')
        try:
            header_data = json.loads(header_data_str) if isinstance(header_data_str, str) else header_data_str
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse header_data JSON: {e}")
            header_data = {}
        
        header_uuid = header_data.get('uuid', event_id)
        header_event_name = header_data.get('eventName', event_name)
        header_event_type = header_data.get('eventType', event_type)
        
        logger.info("=" * 80)
        logger.info(f"Loan Event Header Received (MSK)")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Name: {event_name}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {format_timestamp(created_date)}")
        logger.info(f"  Saved Date: {format_timestamp(saved_date)}")
        logger.info(f"  CDC Operation: {cdc_op}")
        logger.info(f"  CDC Table: {cdc_table}")
        logger.info(f"  Header Data UUID: {header_uuid}")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    """Main consumer loop"""
    logger.info("Starting Loan Consumer (MSK)...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Consumer Group: {CONSUMER_GROUP_ID}")
    logger.info(f"AWS Region: {AWS_REGION}")
    
    if not KAFKA_BOOTSTRAP_SERVERS:
        logger.error("KAFKA_BOOTSTRAP_SERVERS environment variable is required")
        sys.exit(1)
    
    # Create MSK IAM auth token provider
    token_provider = MSKAuthTokenProvider(region=AWS_REGION)
    
    # Configure Kafka consumer with MSK IAM auth
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'client.id': KAFKA_CLIENT_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'security.protocol': 'SASL_SSL',
        'sasl.mechanism': 'AWS_MSK_IAM',
        'sasl.aws.msk.iam.token.provider': token_provider,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,
        'socket.keepalive.enable': True,
        'heartbeat.interval.ms': 10000,
    }
    
    logger.info("Using MSK IAM authentication")
    consumer = Consumer(consumer_config)
    consumer.subscribe([KAFKA_TOPIC])
    
    logger.info("Consumer started. Waiting for messages...")
    
    try:
        while True:
            msg = consumer.poll(timeout=1.0)
            
            if msg is None:
                continue
            
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.debug(f"Reached end of partition {msg.partition()}")
                else:
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
        logger.info("Consumer closed")

if __name__ == '__main__':
    main()

