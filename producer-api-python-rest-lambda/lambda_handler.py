"""Lambda handler for Producer API Python REST."""

import asyncio
import json
import logging
from typing import Any, Dict

import sys
import os

# Add the package directory to the path for Lambda
sys.path.insert(0, os.path.dirname(__file__))

from config import load_lambda_config
from constants import API_NAME
from models.event import Event
from repository import BusinessEventRepository, get_connection_pool
from service import EventProcessingService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Global service instance (reused across invocations)
_service: EventProcessingService | None = None
_config = None


async def _run_migrations(pool):
    """Run database migrations if needed."""
    try:
        # First drop old tables if they exist with old structure
        drop_sql = """
        DROP TABLE IF EXISTS business_events CASCADE;
        DROP TABLE IF EXISTS car_entities CASCADE;
        DROP TABLE IF EXISTS loan_entities CASCADE;
        DROP TABLE IF EXISTS loan_payment_entities CASCADE;
        DROP TABLE IF EXISTS service_record_entities CASCADE;
        DROP TABLE IF EXISTS simple_events CASCADE;
        """
        
        # Use inline schema (data/schema.sql content)
        migration_sql = """
        -- Business Events Table
        CREATE TABLE business_events (
            id VARCHAR(255) PRIMARY KEY,
            event_name VARCHAR(255) NOT NULL,
            event_type VARCHAR(255),
            created_date TIMESTAMP WITH TIME ZONE,
            saved_date TIMESTAMP WITH TIME ZONE,
            event_data JSONB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_business_events_event_type ON business_events(event_type);
        CREATE INDEX IF NOT EXISTS idx_business_events_created_date ON business_events(created_date);
        
        -- Car Entities Table
        CREATE TABLE car_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
        CREATE INDEX IF NOT EXISTS idx_car_entities_created_at ON car_entities(created_at);
        CREATE INDEX IF NOT EXISTS idx_car_entities_updated_at ON car_entities(updated_at);
        
        -- Loan Entities Table
        CREATE TABLE loan_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_loan_entities_entity_type ON loan_entities(entity_type);
        CREATE INDEX IF NOT EXISTS idx_loan_entities_created_at ON loan_entities(created_at);
        CREATE INDEX IF NOT EXISTS idx_loan_entities_updated_at ON loan_entities(updated_at);
        
        -- Loan Payment Entities Table
        CREATE TABLE loan_payment_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_entity_type ON loan_payment_entities(entity_type);
        CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_created_at ON loan_payment_entities(created_at);
        CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_updated_at ON loan_payment_entities(updated_at);
        
        -- Service Record Entities Table
        CREATE TABLE service_record_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_service_record_entities_entity_type ON service_record_entities(entity_type);
        CREATE INDEX IF NOT EXISTS idx_service_record_entities_created_at ON service_record_entities(created_at);
        CREATE INDEX IF NOT EXISTS idx_service_record_entities_updated_at ON service_record_entities(updated_at);
        """
        
        async with pool.acquire() as conn:
            # First drop old tables if they exist
            drop_statements = [s.strip() for s in drop_sql.split(';') if s.strip()]
            for stmt in drop_statements:
                if stmt and not stmt.startswith('--'):
                    try:
                        await conn.execute(stmt)
                    except Exception as e:
                        logger.warning(f"Drop statement warning (may be harmless): {e}")
            
            # Then create new tables
            statements = [s.strip() for s in migration_sql.split(';') if s.strip()]
            for stmt in statements:
                if stmt and not stmt.startswith('--'):
                    try:
                        await conn.execute(stmt)
                    except Exception as e:
                        # Ignore "already exists" errors
                        if "already exists" not in str(e).lower() and "does not exist" not in str(e).lower():
                            logger.warning(f"Migration statement warning: {e}")
        logger.info(f"{API_NAME} Migrations completed")
    except Exception as e:
        logger.error(f"{API_NAME} Migration error: {e}", exc_info=True)


async def _initialize_service():
    """Initialize service with connection pool (singleton pattern)."""
    global _service, _config
    
    if _service is None:
        _config = load_lambda_config()
        
        # Set log level from config
        if _config.log_level == "debug":
            logging.getLogger().setLevel(logging.DEBUG)
        elif _config.log_level == "warn":
            logging.getLogger().setLevel(logging.WARNING)
        elif _config.log_level == "error":
            logging.getLogger().setLevel(logging.ERROR)
        
        # Get connection pool
        pool = await get_connection_pool(_config.database_url)
        
        # Run migrations
        await _run_migrations(pool)
        
        # Initialize repositories and service
        business_event_repo = BusinessEventRepository(pool)
        _service = EventProcessingService(business_event_repo, pool)
        
        logger.info(f"{API_NAME} Lambda handler initialized")
    
    return _service


def _create_response(
    status_code: int, body: Dict[str, Any], headers: Dict[str, str] | None = None
) -> Dict[str, Any]:
    """Create API Gateway HTTP API v2 response."""
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body),
    }


async def _handle_health_check() -> Dict[str, Any]:
    """Handle health check request."""
    return _create_response(
        200,
        {
            "status": "healthy",
            "message": "Producer API is healthy",
        },
    )


async def _handle_process_event(event_body: str) -> Dict[str, Any]:
    """Handle single event processing."""
    try:
        # Parse request body
        event_data = json.loads(event_body)
        event = Event(**event_data)
    except json.JSONDecodeError as e:
        logger.warning(f"{API_NAME} Invalid JSON: {e}")
        return _create_response(
            400,
            {
                "error": "Invalid JSON",
                "status": 400,
            },
        )
    except Exception as e:
        logger.warning(f"{API_NAME} Invalid event structure: {e}")
        return _create_response(
            422,
            {
                "error": f"Invalid event structure: {str(e)}",
                "status": 422,
            },
        )
    
    # Validate event
    if not event.event_header.event_name:
        return _create_response(
            422,
            {
                "error": "Event header event_name is required",
                "status": 422,
            },
        )
    
    if not event.event_body.entities:
        return _create_response(
            422,
            {
                "error": "Event body must contain at least one entity",
                "status": 422,
            },
        )
    
    # Validate each entity
    for entity in event.event_body.entities:
        if not entity.entity_type:
            return _create_response(
                422,
                {
                    "error": "Entity type cannot be empty",
                    "status": 422,
                },
            )
        if not entity.entity_id:
            return _create_response(
                422,
                {
                    "error": "Entity ID cannot be empty",
                    "status": 422,
                },
            )
    
    logger.info(f"{API_NAME} Received event: {event.event_header.event_name}")
    
    # Process event
    try:
        service = await _initialize_service()
        await service.process_event(event)
        
        return _create_response(
            200,
            {
                "success": True,
                "message": "Event processed successfully",
            },
        )
    except Exception as e:
        logger.error(f"{API_NAME} Error processing event: {e}", exc_info=True)
        return _create_response(
            500,
            {
                "error": f"Error processing event: {str(e)}",
                "status": 500,
            },
        )


async def _handle_bulk_events(event_body: str) -> Dict[str, Any]:
    """Handle bulk event processing."""
    try:
        events_data = json.loads(event_body)
        events = [Event(**event_data) for event_data in events_data]
    except json.JSONDecodeError as e:
        logger.warning(f"{API_NAME} Invalid JSON: {e}")
        return _create_response(
            400,
            {
                "error": "Invalid JSON",
                "status": 400,
            },
        )
    except Exception as e:
        logger.warning(f"{API_NAME} Invalid event structure: {e}")
        return _create_response(
            422,
            {
                "error": f"Invalid event structure: {str(e)}",
                "status": 422,
            },
        )
    
    if not events:
        return _create_response(
            422,
            {
                "error": "Invalid request: events list is null or empty",
                "status": 422,
            },
        )
    
    logger.info(f"{API_NAME} Received bulk request with {len(events)} events")
    
    processed_count = 0
    failed_count = 0
    
    service = await _initialize_service()
    
    for event in events:
        try:
            # Validate event
            if not event.event_header.event_name:
                failed_count += 1
                continue
            
            if not event.event_body.entities:
                failed_count += 1
                continue
            
            # Validate entities
            valid = True
            for entity in event.event_body.entities:
                if not entity.entity_type or not entity.entity_id:
                    valid = False
                    break
            
            if not valid:
                failed_count += 1
                continue
            
            await service.process_event(event)
            processed_count += 1
        except Exception as e:
            logger.error(f"{API_NAME} Error processing event in bulk: {e}", exc_info=True)
            failed_count += 1
    
    success = failed_count == 0
    message = (
        "All events processed successfully"
        if success
        else f"Processed {processed_count} events, {failed_count} failed"
    )
    
    return _create_response(
        200,
        {
            "success": success,
            "message": message,
            "processedCount": processed_count,
            "failedCount": failed_count,
            "batchId": f"batch-{int(__import__('time').time() * 1000)}",
            "processingTimeMs": 100,  # Placeholder
        },
    )


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler for API Gateway HTTP API v2."""
    # Lambda Python runtime provides an event loop
    # Use get_event_loop() which returns the running loop or creates one
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # No running loop, get or create one
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
    
    # If loop is closed, create a new one
    if loop.is_closed():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
    
    # Run the async handler
    if loop.is_running():
        # If loop is already running, we need to use a different approach
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor() as executor:
            future = executor.submit(asyncio.run, _async_handler(event, context))
            return future.result()
    else:
        return loop.run_until_complete(_async_handler(event, context))


async def _async_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Async handler implementation."""
    # Extract path and method
    request_context = event.get("requestContext", {})
    http_context = request_context.get("http", {})
    path = http_context.get("path", "")
    method = http_context.get("method", "")
    
    logger.info(f"{API_NAME} Lambda request: {method} {path}")
    
    # Route requests
    if path == "/api/v1/events/health" and method == "GET":
        return await _handle_health_check()
    elif path == "/api/v1/events" and method == "POST":
        body = event.get("body", "{}")
        return await _handle_process_event(body)
    elif path == "/api/v1/events/bulk" and method == "POST":
        body = event.get("body", "[]")
        return await _handle_bulk_events(body)
    else:
        return _create_response(
            404,
            {
                "error": "Not Found",
                "status": 404,
            },
        )
