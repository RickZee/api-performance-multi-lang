#!/usr/bin/env python3
"""
Dealer 002 Consumer (BMW Service Center - Los Angeles)
Consumes filtered service events from Kafka topic: filtered-service-events-dealer-002
Connects to Confluent Cloud Kafka with SASL_SSL authentication
"""

import os
import json
import logging
import sys
import struct
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
logger = logging.getLogger('dealer-002-consumer')

# Configuration from environment variables
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:29092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'filtered-service-events-dealer-002')
KAFKA_API_KEY = os.getenv('KAFKA_API_KEY', '')
KAFKA_API_SECRET = os.getenv('KAFKA_API_SECRET', '')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'dealer-002-service-consumer-group')
DEALER_ID = 'DEALER-002'
DEALER_NAME = 'BMW Service Center - Los Angeles'

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
    """Process a dealer-specific service event"""
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
        header_data_str = event_value.get('header_data', '{}')
        try:
            header_data = json.loads(header_data_str) if isinstance(header_data_str, str) else header_data_str
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse header_data JSON: {e}")
            header_data = {}
        
        # Extract dealerId from header_data (if present) or from entities
        dealer_id = header_data.get('dealerId')
        if not dealer_id:
            # Try to extract from entities if available in header_data
            entities = header_data.get('entities', [])
            if entities and len(entities) > 0:
                dealer_id = entities[0].get('dealerId')
        
        # Verify this event is for our dealer (defensive check)
        if dealer_id and dealer_id != DEALER_ID:
            logger.warning(f"Received event for wrong dealer: {dealer_id}, expected {DEALER_ID}")
            return
        
        # Extract service details from header_data
        car_id = header_data.get('carId')
        service_date = header_data.get('serviceDate')
        amount_paid = header_data.get('amountPaid', 0)
        mileage_at_service = header_data.get('mileageAtService')
        description = header_data.get('description', '')
        
        # Print event information
        logger.info("=" * 80)
        logger.info(f"Service Event for {DEALER_NAME}")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Name: {event_name}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {created_date}")
        logger.info(f"  Saved Date: {saved_date}")
        logger.info(f"  CDC Operation: {cdc_op}")
        logger.info(f"  CDC Table: {cdc_table}")
        logger.info(f"  Service Details:")
        logger.info(f"    Car ID: {car_id}")
        logger.info(f"    Service Date: {service_date}")
        logger.info(f"    Amount Paid: ${amount_paid:.2f}")
        logger.info(f"    Mileage at Service: {mileage_at_service}")
        logger.info(f"    Description: {description}")
        logger.info(f"    Dealer ID: {dealer_id or DEALER_ID}")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    """Main consumer loop"""
    logger.info(f"Starting {DEALER_NAME} Consumer...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Consumer Group: {CONSUMER_GROUP_ID}")
    logger.info(f"Dealer ID: {DEALER_ID}")
    
    # Configure Kafka consumer
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'client.id': 'dealer-002-consumer-client',
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000,
        'socket.keepalive.enable': True,
        'heartbeat.interval.ms': 10000,
        'request.timeout.ms': 40000,
        'socket.timeout.ms': 60000,
        'connections.max.idle.ms': 300000,
        'reconnect.backoff.ms': 100,
        'reconnect.backoff.max.ms': 10000
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
