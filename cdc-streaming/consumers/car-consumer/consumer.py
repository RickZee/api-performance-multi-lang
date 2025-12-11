#!/usr/bin/env python3
"""
Car Consumer
Consumes filtered car created events from Kafka topic: filtered-car-created-events
Connects to Confluent Cloud Kafka with SASL_SSL authentication
"""

import os
import json
import logging
import sys
from datetime import datetime
from confluent_kafka import Consumer, KafkaError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('car-consumer')

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:29092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'filtered-car-created-events')
KAFKA_API_KEY = os.getenv('KAFKA_API_KEY', '')
KAFKA_API_SECRET = os.getenv('KAFKA_API_SECRET', '')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'car-consumer-group')

def process_event(event_value):
    """Process a car event"""
    try:
        # Extract flat structure fields
        event_id = event_value.get('id', 'Unknown')
        event_name = event_value.get('event_name', 'Unknown')
        event_type = event_value.get('event_type', 'Unknown')
        created_date = event_value.get('created_date', 'Unknown')
        saved_date = event_value.get('saved_date', 'Unknown')
        cdc_op = event_value.get('__op', 'Unknown')
        cdc_table = event_value.get('__table', 'Unknown')
        
        # Parse event_data JSON string to access nested structure
        event_data_str = event_value.get('event_data', '{}')
        try:
            event_data = json.loads(event_data_str) if isinstance(event_data_str, str) else event_data_str
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse event_data JSON: {e}")
            event_data = {}
        
        # Extract nested structure
        event_header = event_data.get('eventHeader', {})
        event_body = event_data.get('eventBody', {})
        entities = event_body.get('entities', [])
        
        # Print event information
        logger.info("=" * 80)
        logger.info(f"Car Event Received")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Name: {event_name}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {created_date}")
        logger.info(f"  Saved Date: {saved_date}")
        logger.info(f"  CDC Operation: {cdc_op}")
        logger.info(f"  CDC Table: {cdc_table}")
        
        # Process entities
        for entity in entities:
            entity_type = entity.get('entityType', 'Unknown')
            entity_id = entity.get('entityId', 'Unknown')
            updated_attrs = entity.get('updatedAttributes', {})
            
            logger.info(f"  Entity Type: {entity_type}, Entity ID: {entity_id}")
            
            # Process car-specific attributes
            if entity_type == 'Car':
                car_data = updated_attrs.get('car', {})
                if car_data:
                    logger.info(f"    VIN: {car_data.get('vin', 'N/A')}")
                    logger.info(f"    Make: {car_data.get('make', 'N/A')}")
                    logger.info(f"    Model: {car_data.get('model', 'N/A')}")
                    logger.info(f"    Year: {car_data.get('year', 'N/A')}")
                    logger.info(f"    Color: {car_data.get('color', 'N/A')}")
                    logger.info(f"    Mileage: {car_data.get('mileage', 'N/A')}")
                    logger.info(f"    Status: {car_data.get('status', 'N/A')}")
        
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    """Main consumer loop"""
    logger.info("Starting Car Consumer...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Consumer Group: {CONSUMER_GROUP_ID}")
    
    # Configure Kafka consumer
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,
        # Network keepalive and timeout settings for Confluent Cloud
        'socket.keepalive.enable': True,  # Enable TCP keepalive to prevent idle connection drops
        'heartbeat.interval.ms': 10000,  # Should be 1/3 of session.timeout.ms
        'request.timeout.ms': 40000,  # Should be higher than session.timeout.ms
        'socket.timeout.ms': 60000,  # Network socket timeout
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
                # Deserialize JSON message
                event_value = json.loads(msg.value().decode('utf-8'))
                
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
