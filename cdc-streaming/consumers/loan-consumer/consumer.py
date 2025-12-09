#!/usr/bin/env python3
"""
Loan Consumer Example
Consumes filtered loan events from Kafka topic: filtered-loan-events
"""

import os
import json
import logging
import sys
from datetime import datetime
from confluent_kafka import Consumer, KafkaError
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField

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
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://schema-registry:8081')
CONSUMER_GROUP_ID = os.getenv('CONSUMER_GROUP_ID', 'loan-consumer-group')

def process_event(event_value):
    """Process a loan event"""
    try:
        event_header = event_value.get('eventHeader', {})
        event_body = event_value.get('eventBody', {})
        filter_metadata = event_value.get('filterMetadata', {})
        
        event_name = event_header.get('eventName', 'Unknown')
        entities = event_body.get('entities', [])
        
        logger.info(f"Received loan event: {event_name}")
        logger.info(f"Filter ID: {filter_metadata.get('filterId', 'N/A')}")
        logger.info(f"Consumer ID: {filter_metadata.get('consumerId', 'N/A')}")
        
        for entity in entities:
            entity_type = entity.get('entityType', 'Unknown')
            entity_id = entity.get('entityId', 'Unknown')
            updated_attrs = entity.get('updatedAttributes', {})
            
            logger.info(f"  Entity Type: {entity_type}, Entity ID: {entity_id}")
            
            # Process loan-specific attributes
            if entity_type == 'Loan':
                loan_data = updated_attrs.get('loan', {})
                if loan_data:
                    logger.info(f"    Loan Amount: {loan_data.get('loanAmount', 'N/A')}")
                    logger.info(f"    Balance: {loan_data.get('balance', 'N/A')}")
                    logger.info(f"    Status: {loan_data.get('status', 'N/A')}")
            elif entity_type == 'LoanPayment':
                payment_data = updated_attrs.get('loanPayment', {})
                if payment_data:
                    logger.info(f"    Payment Amount: {payment_data.get('amount', 'N/A')}")
                    logger.info(f"    Payment Date: {payment_data.get('paymentDate', 'N/A')}")
        
        logger.info("-" * 80)
        
    except Exception as e:
        logger.error(f"Error processing event: {e}", exc_info=True)

def main():
    """Main consumer loop"""
    logger.info("Starting Loan Consumer...")
    logger.info(f"Bootstrap Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Topic: {KAFKA_TOPIC}")
    logger.info(f"Schema Registry: {SCHEMA_REGISTRY_URL}")
    logger.info(f"Consumer Group: {CONSUMER_GROUP_ID}")
    
    # Configure Kafka consumer
    consumer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': CONSUMER_GROUP_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': True,
        'session.timeout.ms': 30000,
        'max.poll.interval.ms': 300000
    }
    
    consumer = Consumer(consumer_config)
    consumer.subscribe([KAFKA_TOPIC])
    
    # Setup Schema Registry and Avro Deserializer
    schema_registry_client = SchemaRegistryClient({'url': SCHEMA_REGISTRY_URL})
    
    # For simplicity, we'll use JSON deserializer if Avro is not available
    # In production, use AvroDeserializer with proper schema
    use_avro = os.getenv('USE_AVRO', 'false').lower() == 'true'
    
    if use_avro:
        # Get the latest schema version
        try:
            subject = f"{KAFKA_TOPIC}-value"
            schema = schema_registry_client.get_latest_version(subject)
            avro_deserializer = AvroDeserializer(
                schema_registry_client,
                schema.schema.schema_str
            )
            logger.info("Using Avro deserializer")
        except Exception as e:
            logger.warning(f"Could not load Avro schema, using JSON: {e}")
            use_avro = False
    
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
                # Deserialize message
                if use_avro:
                    event_value = avro_deserializer(
                        msg.value(),
                        SerializationContext(msg.topic(), MessageField.VALUE)
                    )
                else:
                    # Fallback to JSON
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






