#!/usr/bin/env python3
"""
Shared base module for MSK consumers
Provides common functionality for all MSK consumers
"""

import os
import json
import logging
import sys
from datetime import datetime
from typing import Dict, Any, Optional, Callable
from confluent_kafka import Consumer, KafkaError
from aws_msk_iam_sasl_signer_python import MSKAuthTokenProvider

try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo


class MSKConsumerBase:
    """Base class for MSK consumers with common functionality"""
    
    def __init__(
        self,
        consumer_name: str,
        default_topic: str,
        default_group_id: str,
        process_event_callback: Callable[[Dict[str, Any]], None]
    ):
        """
        Initialize MSK consumer base
        
        Args:
            consumer_name: Name of the consumer (for logging)
            default_topic: Default Kafka topic name
            default_group_id: Default consumer group ID
            process_event_callback: Callback function to process events
        """
        self.consumer_name = consumer_name
        self.default_topic = default_topic
        self.default_group_id = default_group_id
        self.process_event_callback = process_event_callback
        
        # Configure logging
        self.logger = self._setup_logging()
        
        # Load configuration from environment
        self.config = self._load_config()
        
        # Validate configuration
        self._validate_config()
        
        # Consumer instance (created in start)
        self.consumer: Optional[Consumer] = None
    
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[logging.StreamHandler(sys.stdout)]
        )
        return logging.getLogger(self.consumer_name)
    
    def _load_config(self) -> Dict[str, str]:
        """Load configuration from environment variables"""
        config = {
            'bootstrap_servers': os.getenv('KAFKA_BOOTSTRAP_SERVERS', ''),
            'topic': os.getenv('KAFKA_TOPIC', self.default_topic),
            'aws_region': os.getenv('AWS_REGION', 'us-east-1'),
            'consumer_group_id': os.getenv('CONSUMER_GROUP_ID', self.default_group_id),
            'display_timezone': os.getenv('DISPLAY_TIMEZONE', 'America/New_York'),
        }
        
        # Derive client ID from group ID if not set
        default_client_id = config['consumer_group_id'].replace('-group', '-client')
        config['client_id'] = os.getenv('KAFKA_CLIENT_ID', default_client_id)
        
        return config
    
    def _validate_config(self) -> None:
        """Validate required configuration"""
        if not self.config['bootstrap_servers']:
            self.logger.error("KAFKA_BOOTSTRAP_SERVERS environment variable is required")
            sys.exit(1)
    
    def format_timestamp(self, utc_timestamp_str: str) -> str:
        """
        Convert UTC ISO 8601 timestamp to local time display format.
        
        Args:
            utc_timestamp_str: ISO 8601 UTC timestamp string
            
        Returns:
            Formatted string with UTC and local time
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
            
            # Convert to local timezone
            try:
                display_tz = ZoneInfo(self.config['display_timezone'])
                dt_local = dt_utc.astimezone(display_tz)
                tz_abbr = dt_local.strftime('%Z')
                local_str = dt_local.strftime('%Y-%m-%d %H:%M:%S')
                return f"{utc_timestamp_str} (Local: {local_str} {tz_abbr})"
            except Exception as e:
                self.logger.warning(f"Failed to convert to timezone {self.config['display_timezone']}: {e}")
                return utc_timestamp_str
        except Exception as e:
            self.logger.warning(f"Failed to parse timestamp '{utc_timestamp_str}': {e}")
            return utc_timestamp_str
    
    def _create_consumer(self) -> Consumer:
        """Create and configure Kafka consumer with MSK IAM authentication"""
        # Create MSK IAM auth token provider
        token_provider = MSKAuthTokenProvider(region=self.config['aws_region'])
        
        # Configure Kafka consumer with MSK IAM auth
        consumer_config = {
            'bootstrap.servers': self.config['bootstrap_servers'],
            'group.id': self.config['consumer_group_id'],
            'client.id': self.config['client_id'],
            'auto.offset.reset': 'earliest',
            'enable.auto.commit': True,
            'security.protocol': 'SASL_SSL',
            'sasl.mechanism': 'AWS_MSK_IAM',
            'sasl.aws.msk.iam.token.provider': token_provider,
            'session.timeout.ms': 30000,
            'max.poll.interval.ms': 300000,
            'socket.keepalive.enable': True,
            'heartbeat.interval.ms': 10000,
            'socket.timeout.ms': 60000,
            'connections.max.idle.ms': 300000,
            'reconnect.backoff.ms': 100,
            'reconnect.backoff.max.ms': 10000,
        }
        
        self.logger.info("Using MSK IAM authentication")
        consumer = Consumer(consumer_config)
        consumer.subscribe([self.config['topic']])
        
        return consumer
    
    def start(self) -> None:
        """Start the consumer and begin processing messages"""
        self.logger.info(f"Starting {self.consumer_name} (MSK)...")
        self.logger.info(f"Bootstrap Servers: {self.config['bootstrap_servers']}")
        self.logger.info(f"Topic: {self.config['topic']}")
        self.logger.info(f"Consumer Group: {self.config['consumer_group_id']}")
        self.logger.info(f"AWS Region: {self.config['aws_region']}")
        self.logger.info(f"Client ID: {self.config['client_id']}")
        
        # Create consumer
        self.consumer = self._create_consumer()
        self.logger.info("Consumer started. Waiting for messages...")
        
        # Process messages
        self._consume_messages()
    
    def _consume_messages(self) -> None:
        """Main message consumption loop"""
        try:
            while True:
                msg = self.consumer.poll(timeout=1.0)
                
                if msg is None:
                    continue
                
                if msg.error():
                    if msg.error().code() == KafkaError._PARTITION_EOF:
                        self.logger.debug(f"Reached end of partition {msg.partition()}")
                    else:
                        self.logger.error(f"Consumer error: {msg.error()}")
                    continue
                
                try:
                    # Parse message value
                    event_value = json.loads(msg.value().decode('utf-8'))
                    
                    # Process event using callback
                    self.process_event_callback(event_value)
                    
                except json.JSONDecodeError as e:
                    self.logger.error(f"Failed to parse message JSON: {e}")
                    self.logger.debug(f"Message value: {msg.value()}")
                except Exception as e:
                    self.logger.error(f"Error processing message: {e}", exc_info=True)
                    
        except KeyboardInterrupt:
            self.logger.info("Shutting down consumer...")
        except Exception as e:
            self.logger.error(f"Fatal error in consumer loop: {e}", exc_info=True)
            raise
        finally:
            self.close()
    
    def close(self) -> None:
        """Close the consumer"""
        if self.consumer:
            self.consumer.close()
            self.logger.info("Consumer closed")

