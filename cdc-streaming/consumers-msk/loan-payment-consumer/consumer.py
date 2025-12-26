#!/usr/bin/env python3
"""
Loan Payment Consumer for MSK
Consumes filtered loan payment events from MSK topic: filtered-loan-payment-submitted-events-msk
Connects to Amazon MSK with IAM authentication
"""

import sys
import os
import json
import logging

# Add shared module to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'shared'))

from msk_consumer_base import MSKConsumerBase

logger = logging.getLogger('loan-payment-consumer-msk')

def process_loan_payment_event(event_value: dict) -> None:
    """Process a loan payment event"""
    try:
        event_id = event_value.get('id', 'Unknown')
        event_name = event_value.get('event_name', 'Unknown')
        event_type = event_value.get('event_type', 'Unknown')
        created_date = event_value.get('created_date', 'Unknown')
        saved_date = event_value.get('saved_date', 'Unknown')
        cdc_op = event_value.get('__op', 'Unknown')
        cdc_table = event_value.get('__table', 'Unknown')
        
        # Parse header_data JSON
        header_data_str = event_value.get('header_data', '{}')
        try:
            header_data = json.loads(header_data_str) if isinstance(header_data_str, str) else header_data_str
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse header_data JSON: {e}")
            header_data = {}
        
        header_uuid = header_data.get('uuid', event_id)
        
        logger.info("=" * 80)
        logger.info(f"Loan Payment Event Received (MSK)")
        logger.info(f"  Event ID: {event_id}")
        logger.info(f"  Event Name: {event_name}")
        logger.info(f"  Event Type: {event_type}")
        logger.info(f"  Created Date: {created_date}")
        logger.info(f"  Saved Date: {saved_date}")
        logger.info(f"  CDC Operation: {cdc_op}")
        logger.info(f"  CDC Table: {cdc_table}")
        logger.info(f"  Header Data UUID: {header_uuid}")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error processing loan payment event: {e}", exc_info=True)

def main():
    """Main entry point"""
    consumer = MSKConsumerBase(
        consumer_name='loan-payment-consumer-msk',
        default_topic='filtered-loan-payment-submitted-events-msk',
        default_group_id='loan-payment-consumer-group-msk',
        process_event_callback=process_loan_payment_event
    )
    consumer.start()

if __name__ == '__main__':
    main()
