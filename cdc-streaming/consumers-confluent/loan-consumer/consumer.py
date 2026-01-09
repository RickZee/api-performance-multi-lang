#!/usr/bin/env python3
"""
Loan Consumer
Consumes filtered loan created events from Kafka topic: filtered-loan-created-events
Connects to Confluent Cloud Kafka with SASL_SSL authentication
"""

import os
import json
import logging
import sys
import struct
import time
from datetime import datetime
from confluent_kafka import Consumer, KafkaError

try:
    from zoneinfo import ZoneInfo
except ImportError:
    # Fallback for Python < 3.9
    from backports.zoneinfo import ZoneInfo

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('loan-consumer')

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:29092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'filtered-loan-created-events')
KAFKA_API_KEY = os.getenv('KAFKA_API_KEY', '')
KAFKA_API_SECRET = os.getenv('KAFKA_API_SECRET', '')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'loan-consumer-group')
# Client ID: Use environment variable if set, otherwise derive from consumer group ID
# This ensures uniqueness between Spring and Flink consumers (which have different group IDs)
KAFKA_CLIENT_ID = os.getenv('KAFKA_CLIENT_ID', CONSUMER_GROUP_ID.replace('-group', '-client'))
DISPLAY_TIMEZONE = os.getenv('DISPLAY_TIMEZONE', 'America/New_York')

def format_timestamp(utc_timestamp_str):
    """
    Convert UTC ISO 8601 timestamp to local time display format.
    Returns formatted string with both UTC and local time.
    
    Args:
        utc_timestamp_str: ISO 8601 UTC timestamp string (e.g., '2024-01-15T10:30:00Z')
    
    Returns:
        Formatted string: 'UTC_TIMESTAMP (Local: LOCAL_TIME TIMEZONE)'
    """
    if not utc_timestamp_str or utc_timestamp_str == 'Unknown':
        return utc_timestamp_str
    
    try:
        # Parse UTC timestamp
        if utc_timestamp_str.endswith('Z'):
            dt_utc = datetime.fromisoformat(utc_timestamp_str.replace('Z', '+00:00'))
        else:
            dt_utc = datetime.fromisoformat(utc_timestamp_str)
            if dt_utc.tzinfo is None:
                dt_utc = dt_utc.replace(tzinfo=ZoneInfo('UTC'))
        
        # Convert to display timezone
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

def deserialize_json_schema_registry(msg_value):
    """
    Deserialize JSON Schema Registry format.
    Format: [0x00][4-byte schema ID][JSON payload]
    """
    if not msg_value:
        return None
    
    try:
        # Check if message starts with magic byte (0x00 for JSON Schema Registry)
        if msg_value[0] != 0:
            # Not Schema Registry format, try plain JSON
            return json.loads(msg_value.decode('utf-8'))
        
        # Skip magic byte (1 byte) and schema ID (4 bytes)
        # Extract JSON payload starting from byte 5
        json_payload = msg_value[5:].decode('utf-8')
        return json.loads(json_payload)
    except (IndexError, struct.error, UnicodeDecodeError, json.JSONDecodeError) as e:
        logger.warning(f"Failed to deserialize Schema Registry format, trying plain JSON: {e}")
        # Fallback to plain JSON
        try:
            return json.loads(msg_value.decode('utf-8'))
        except Exception as e2:
            logger.error(f"Failed to deserialize as plain JSON: {e2}")
            raise

def process_event(event_value):
    """Process a loan event"""
    try:
        # Extract flat structure fields
        event_id = event_value.get('id', 'Unknown')
        event_name = event_value.get('event_name', 'Unknown')
        event_type = event_value.get('event_type', 'Unknown')
        created_date = event_value.get('created_date', 'Unknown')
        saved_date = event_value.get('saved_date', 'Unknown')
        cdc_op = event_value.get('__op', 'Unknown')
        cdc_table = event_value.get('__table', 'Unknown')
        
        # Parse header_data JSON string to access event header structure
        # Note: header_data contains only eventHeader, not entities (which are in event_data at root level)
        header_data_str = event_value.get('header_data', '{}')
        try:
            header_data = json.loads(header_data_str) if isinstance(header_data_str, str) else header_data_str
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse header_data JSON: {e}")
            header_data = {}
        
        # Extract header fields from header_data
        header_uuid = header_data.get('uuid', event_id)
        header_event_name = header_data.get('eventName', event_name)
        header_event_type = header_data.get('eventType', event_type)
        header_created_date = header_data.get('createdDate', created_date)
        header_saved_date = header_data.get('savedDate', saved_date)
        
        # Print event information
        logger.info("=" * 80)
        logger.info(f"Loan Event Header Received")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Name: {event_name}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {format_timestamp(created_date)}")
        logger.info(f"  Saved Date: {format_timestamp(saved_date)}")
        logger.info(f"  CDC Operation: {cdc_op}")
        logger.info(f"  CDC Table: {cdc_table}")
        logger.info(f"  Header Data:")
        logger.info(f"    UUID: {header_uuid}")
        logger.info(f"    Event Name: {header_event_name}")
        logger.info(f"    Event Type: {header_event_type}")
        logger.info(f"    Created Date: {format_timestamp(header_created_date)}")
        logger.info(f"    Saved Date: {format_timestamp(header_saved_date)}")
        logger.info(f"  Note: Entity information is not available in event_headers stream.")
        logger.info(f"        Query database using event_id to retrieve associated entities.")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    """Main consumer loop"""
    logger.info("Starting Loan Consumer...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Consumer Group: {CONSUMER_GROUP_ID}")
    
    # Configure Kafka consumer
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'client.id': KAFKA_CLIENT_ID,  # Unique client ID for monitoring and quota management (derived from consumer group ID)
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,
        # Network keepalive and timeout settings for Confluent Cloud
        'socket.keepalive.enable': True,  # Enable TCP keepalive to prevent idle connection drops
        'heartbeat.interval.ms': 10000,  # Should be 1/3 of session.timeout.ms
        'socket.timeout.ms': 60000,  # Network socket timeout (consumer property)
        'connections.max.idle.ms': 300000,  # 5 minutes - prevent idle connection drops
        'reconnect.backoff.ms': 100,  # Initial reconnect backoff
        'reconnect.backoff.max.ms': 10000  # Max reconnect backoff
    }
    
    # Add Confluent Cloud authentication if API key/secret are provided
    if KAFKA_API_KEY and KAFKA_API_SECRET:
        consumer_config.update({
            'security.protocol': 'SASL_SSL',
            'sasl.mechanism': 'PLAIN',
            'sasl.username': KAFKA_API_KEY,
            'sasl.password': KAFKA_API_SECRET
        })
        logger.info("Using Confluent Cloud SASL_SSL authentication")
    else:
        logger.info("Using local Kafka (no authentication)")
    
    logger.info(f"Client ID: {consumer_config.get('client.id', 'NOT SET')}")
    
    # Retry topic subscription with backoff for topic creation delays
    # Note: subscribe() doesn't throw immediately, errors appear during poll()
    max_subscribe_retries = 10
    subscribe_retry_interval = 5
    consumer = None
    subscription_successful = False
    
    for retry_count in range(max_subscribe_retries):
        try:
            if consumer:
                consumer.close()
            consumer = Consumer(consumer_config)
            consumer.subscribe([KAFKA_TOPIC])
            
            # Poll a few times to check if topic is available
            # Errors appear during poll, not subscribe
            topic_available = False
            for poll_attempt in range(3):
                msg = consumer.poll(timeout=1.0)
                if msg is None:
                    # No message but no error - topic might be available
                    topic_available = True
                    break
                if msg.error():
                    error_code = msg.error().code()
                    if error_code == KafkaError.UNKNOWN_TOPIC_OR_PART:
                        logger.warning(f"Topic {KAFKA_TOPIC} not available yet (poll attempt {poll_attempt + 1}/3)")
                        topic_available = False
                        break
                    elif error_code == KafkaError._PARTITION_EOF:
                        # Topic exists but no messages yet - this is OK
                        topic_available = True
                        break
                    else:
                        # Other error - assume topic might be available
                        topic_available = True
                        break
                else:
                    # Got a message - topic is definitely available
                    topic_available = True
                    break
            
            if topic_available:
                logger.info("Consumer started. Waiting for messages...")
                subscription_successful = True
                break
            else:
                if retry_count < max_subscribe_retries - 1:
                    logger.warning(f"Topic {KAFKA_TOPIC} not available yet (retry {retry_count + 1}/{max_subscribe_retries}), waiting {subscribe_retry_interval}s...")
                    consumer.close()
                    consumer = None
                    time.sleep(subscribe_retry_interval)
                    continue
                else:
                    logger.error(f"Topic {KAFKA_TOPIC} not available after {max_subscribe_retries} retries. Exiting.")
                    if consumer:
                        consumer.close()
                    return
        except Exception as e:
            logger.error(f"Consumer error during subscription: {e}")
            if consumer:
                consumer.close()
                consumer = None
            if retry_count < max_subscribe_retries - 1:
                logger.warning(f"Retrying subscription (retry {retry_count + 1}/{max_subscribe_retries})...")
                time.sleep(subscribe_retry_interval)
                continue
            else:
                logger.error("Failed to create consumer after retries")
                return
    
    if consumer is None or not subscription_successful:
        logger.error("Failed to create consumer after retries")
        return
    
    try:
        consecutive_unknown_topic_errors = 0
        max_unknown_topic_errors = 20  # Allow up to 20 consecutive errors before retrying subscription
        
        while True:
            msg = consumer.poll(timeout=1.0)
            
            if msg is None:
                continue
            
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.debug(f"Reached end of partition {msg.partition()}")
                    consecutive_unknown_topic_errors = 0  # Reset error counter on successful poll
                elif msg.error().code() == KafkaError.UNKNOWN_TOPIC_OR_PART:
                    consecutive_unknown_topic_errors = consecutive_unknown_topic_errors + 1
                    if consecutive_unknown_topic_errors < max_unknown_topic_errors:
                        logger.warning(f"Topic {KAFKA_TOPIC} not available (error {consecutive_unknown_topic_errors}/{max_unknown_topic_errors}), will retry...")
                        time.sleep(subscribe_retry_interval)
                        continue
                    else:
                        logger.warning(f"Topic {KAFKA_TOPIC} still not available after {max_unknown_topic_errors} errors, re-subscribing...")
                        # Close and recreate consumer to retry subscription
                        consumer.close()
                        time.sleep(subscribe_retry_interval)
                        consumer = Consumer(consumer_config)
                        consumer.subscribe([KAFKA_TOPIC])
                        consecutive_unknown_topic_errors = 0
                        continue
                else:
                    logger.error(f"Consumer error: {msg.error()}")
                    consecutive_unknown_topic_errors = 0  # Reset on other errors
                continue
            
            # Reset error counter on successful message
            consecutive_unknown_topic_errors = 0
            
            try:
                # Deserialize JSON Schema Registry format message
                event_value = deserialize_json_schema_registry(msg.value())
                
                if event_value is None:
                    logger.warning("Received None event value, skipping")
                    continue
                
                # Process the event
                process_event(event_value)
                
            except Exception as e:
                logger.error(f"Error deserializing/processing message: {e}", exc_info=True)
                
    except KeyboardInterrupt:
        logger.info("Shutting down consumer...")
    finally:
        consumer.close()
        logger.info("Consumer closed")

if __name__ == '__main__':
    main()
