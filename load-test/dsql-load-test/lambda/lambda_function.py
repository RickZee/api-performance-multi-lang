"""Standalone Lambda handler for DSQL load testing."""

import asyncio
import json
import logging
import time
from typing import Any, Dict, Optional
from datetime import datetime

from config import load_lambda_config
from connection import get_connection
from repository import create_batch, create_individual
from event_generators import (
    generate_car_created_event,
    generate_loan_created_event,
    generate_loan_payment_event,
    generate_car_service_event,
    generate_uuid,
    generate_timestamp
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Global config (initialized on first use)
_config = None


def _get_event_generator(event_type: str):
    """Get the appropriate event generator function based on event_type."""
    generators = {
        "CarCreated": generate_car_created_event,
        "LoanCreated": generate_loan_created_event,
        "LoanPaymentSubmitted": generate_loan_payment_event,
        "CarServiceDone": generate_car_service_event,
    }
    return generators.get(event_type, generate_car_created_event)


def _generate_unique_event_id(scenario: str, lambda_index: int, iteration: int, insert_index: int) -> str:
    """Generate a unique event ID to avoid conflicts."""
    timestamp = int(time.time() * 1000)  # milliseconds
    return f"load-test-{scenario}-{lambda_index}-{iteration}-{insert_index}-{timestamp}"


def _prepare_event_for_insert(event_dict: Dict, event_id: str) -> Dict:
    """Prepare event dict for database insert."""
    event_header = event_dict.get("eventHeader", {})
    entities = event_dict.get("entities", [])
    
    if not entities:
        raise ValueError("Event must have at least one entity")
    
    entity = entities[0]
    entity_header = entity.get("entityHeader", {})
    
    return {
        "event_id": event_id,
        "event_name": event_header.get("eventName", ""),
        "event_type": event_header.get("eventType", ""),
        "created_date": datetime.fromisoformat(event_header.get("createdDate", "").replace('Z', '+00:00')) if event_header.get("createdDate") else datetime.utcnow(),
        "saved_date": datetime.fromisoformat(event_header.get("savedDate", "").replace('Z', '+00:00')) if event_header.get("savedDate") else datetime.utcnow(),
        "event_data": event_dict  # Full event JSON
    }


async def _run_individual_scenario(
    conn,
    iterations: int,
    count: int,
    event_type: str,
    lambda_index: int
) -> Dict[str, Any]:
    """Run individual insert scenario with loop."""
    import asyncpg
    start_time = time.time()
    success_count = 0
    error_count = 0
    
    generator = _get_event_generator(event_type)
    
    try:
        for i in range(iterations):
            for j in range(count):
                try:
                    # Generate event
                    if event_type == "LoanCreated":
                        car_id = f"CAR-{lambda_index}-{i}-{j}"
                        event_dict = generator(car_id=car_id)
                    elif event_type == "LoanPaymentSubmitted":
                        loan_id = f"LOAN-{lambda_index}-{i}-{j}"
                        event_dict = generator(loan_id=loan_id)
                    elif event_type == "CarServiceDone":
                        car_id = f"CAR-{lambda_index}-{i}-{j}"
                        event_dict = generator(car_id=car_id)
                    else:
                        event_dict = generator()
                    
                    # Generate unique event ID
                    event_id = _generate_unique_event_id("individual", lambda_index, i, j)
                    
                    # Prepare event for insert
                    event_data = _prepare_event_for_insert(event_dict, event_id)
                    
                    # Insert individual event
                    await create_individual(event_data, conn)
                    success_count += 1
                except Exception as e:
                    logger.error(f"Error in individual insert iteration {i}, insert {j}: {e}")
                    error_count += 1
        
        duration_ms = (time.time() - start_time) * 1000
        inserts_per_second = (success_count / duration_ms * 1000) if duration_ms > 0 else 0
        
        return {
            "success_count": success_count,
            "error_count": error_count,
            "duration_ms": duration_ms,
            "inserts_per_second": inserts_per_second,
            "total_inserts": iterations * count
        }
    except Exception as e:
        logger.error(f"Error in individual scenario: {e}", exc_info=True)
        raise


async def _run_batch_scenario(
    conn,
    iterations: int,
    batch_size: int,
    event_type: str,
    lambda_index: int
) -> Dict[str, Any]:
    """Run batch insert scenario with loop."""
    start_time = time.time()
    success_count = 0
    error_count = 0
    
    generator = _get_event_generator(event_type)
    
    try:
        for i in range(iterations):
            try:
                # Generate batch of events
                events = []
                for j in range(batch_size):
                    # Generate event
                    if event_type == "LoanCreated":
                        car_id = f"CAR-{lambda_index}-{i}-{j}"
                        event_dict = generator(car_id=car_id)
                    elif event_type == "LoanPaymentSubmitted":
                        loan_id = f"LOAN-{lambda_index}-{i}-{j}"
                        event_dict = generator(loan_id=loan_id)
                    elif event_type == "CarServiceDone":
                        car_id = f"CAR-{lambda_index}-{i}-{j}"
                        event_dict = generator(car_id=car_id)
                    else:
                        event_dict = generator()
                    
                    # Generate unique event ID
                    event_id = _generate_unique_event_id("batch", lambda_index, i, j)
                    
                    # Prepare event for insert
                    event_data = _prepare_event_for_insert(event_dict, event_id)
                    events.append(event_data)
                
                # Insert batch
                inserted = await create_batch(events, conn)
                success_count += inserted
            except Exception as e:
                logger.error(f"Error in batch insert iteration {i}: {e}")
                error_count += batch_size
        
        duration_ms = (time.time() - start_time) * 1000
        inserts_per_second = (success_count / duration_ms * 1000) if duration_ms > 0 else 0
        
        return {
            "success_count": success_count,
            "error_count": error_count,
            "duration_ms": duration_ms,
            "inserts_per_second": inserts_per_second,
            "total_inserts": iterations * batch_size
        }
    except Exception as e:
        logger.error(f"Error in batch scenario: {e}", exc_info=True)
        raise


async def _process_load_test(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Process load test request."""
    global _config
    
    if _config is None:
        _config = load_lambda_config()
    
    scenario = payload.get("scenario", "individual")
    count = payload.get("count", 1)
    iterations = payload.get("iterations", 10)
    event_type = payload.get("event_type", "CarCreated")
    lambda_index = payload.get("lambda_index", 0)
    
    logger.info(
        f"Starting load test: scenario={scenario}, iterations={iterations}, count={count}, event_type={event_type}, lambda_index={lambda_index}"
    )
    
    # Get database connection
    conn = await get_connection(_config)
    
    try:
        if scenario == "individual":
            result = await _run_individual_scenario(conn, iterations, count, event_type, lambda_index)
        elif scenario == "batch":
            result = await _run_batch_scenario(conn, iterations, count, event_type, lambda_index)
        else:
            raise ValueError(f"Unknown scenario: {scenario}")
        
        result["scenario"] = scenario
        result["iterations"] = iterations
        result["count"] = count
        result["event_type"] = event_type
        result["lambda_index"] = lambda_index
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "success": True,
                "result": result
            })
        }
    except Exception as e:
        logger.error(f"Error processing load test: {e}", exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({
                "success": False,
                "error": str(e)
            })
        }
    finally:
        await conn.close()


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Standalone Lambda handler for DSQL load testing."""
    try:
        # Handle both direct invocation and API Gateway events
        if "body" in event:
            # API Gateway event
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        else:
            # Direct Lambda invocation
            body = event
        
        return asyncio.run(_process_load_test(body))
    except Exception as e:
        logger.error(f"Error in lambda_handler: {e}", exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({
                "success": False,
                "error": str(e)
            })
        }
