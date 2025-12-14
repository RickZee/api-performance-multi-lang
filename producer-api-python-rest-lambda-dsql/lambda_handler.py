"""Lambda handler for Producer API Python REST."""

import asyncio
import json
import logging
from typing import Any, Dict, Optional

import sys
import os
import boto3

# Add the package directory to the path for Lambda
sys.path.insert(0, os.path.dirname(__file__))

from config import load_lambda_config
from constants import API_NAME
from producer_api_shared.models import Event
from producer_api_shared.repository import BusinessEventRepository
from producer_api_shared.exceptions import DuplicateEventError
from producer_api_shared.service import EventProcessingService
from repository import get_connection

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Global service instance (reused across invocations)
_service: EventProcessingService | None = None
_config = None

# Module-level dedicated event loop for Lambda handler
# This ensures we always use the same loop for asyncpg pool creation/usage
_lambda_loop: Optional[asyncio.AbstractEventLoop] = None
_lambda_client = None


async def _initialize_service():
    """Initialize service (no pool, connections created per invocation)."""
    global _service, _config, _lambda_client
    
    if _service is None:
        _config = load_lambda_config()
        
        # Set log level from config
        if _config.log_level == "debug":
            logging.getLogger().setLevel(logging.DEBUG)
        elif _config.log_level == "warn":
            logging.getLogger().setLevel(logging.WARNING)
        elif _config.log_level == "error":
            logging.getLogger().setLevel(logging.ERROR)
        
        # Initialize Lambda client for auto-start functionality
        _lambda_client = boto3.client('lambda', region_name=os.getenv('AWS_REGION', 'us-east-1'))
        
        # Initialize repositories and service with connection factory
        business_event_repo = BusinessEventRepository()
        
        # Create connection factory for direct connections (DSQL pattern)
        async def connection_factory():
            return await get_connection(_config)
        
        _service = EventProcessingService(
            business_event_repo=business_event_repo,
            connection_factory=connection_factory,
            api_name=API_NAME,
            should_close_connection=True  # Close direct connections after use
        )
        
        logger.info(f"{API_NAME} Lambda handler initialized (using direct connections)")
    
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


async def _try_start_database() -> Optional[Dict[str, Any]]:
    """Attempt to start the database if it's stopped. Returns error response if DB is starting, None otherwise."""
    global _lambda_client
    
    auto_start_function = os.getenv('AURORA_AUTO_START_FUNCTION_NAME')
    if not auto_start_function:
        # Auto-start not configured, skip
        return None
    
    try:
        # Invoke the auto-start Lambda
        response = _lambda_client.invoke(
            FunctionName=auto_start_function,
            InvocationType='RequestResponse'
        )
        
        response_payload = json.loads(response['Payload'].read().decode('utf-8'))
        
        if response_payload.get('statusCode') == 200:
            body = json.loads(response_payload.get('body', '{}'))
            status = body.get('status', '')
            
            if status == 'starting':
                # Database is starting, return user-friendly message
                return _create_response(
                    503,
                    {
                        "error": "Service Temporarily Unavailable",
                        "message": "The database is currently starting. Please retry your request in 1-2 minutes.",
                        "status": 503,
                        "retry_after": 120,  # seconds
                    },
                    headers={"Retry-After": "120"}
                )
            elif status in ['available', 'transitioning']:
                # Database is available or transitioning, allow request to proceed
                return None
    except Exception as e:
        logger.warning(f"{API_NAME} Failed to check/start database: {e}")
        # Don't block the request if we can't check database status
        return None
    
    return None


def _is_database_connection_error(error: Exception) -> bool:
    """Check if error is a database connection error."""
    error_str = str(error).lower()
    connection_errors = [
        'connection refused',
        'connection reset',
        'connection timed out',
        'could not connect',
        'unable to connect',
        'network is unreachable',
        'no route to host',
        'connection closed',
        'server closed the connection',
        'timeout expired',
        'could not translate host name',
    ]
    return any(err in error_str for err in connection_errors)


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
    
    # Validate each entity (Pydantic models handle validation automatically)
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
    except DuplicateEventError as e:
        # Handle duplicate event ID (409 Conflict)
        logger.warning(f"{API_NAME} Duplicate event ID: {e.event_id}")
        return _create_response(
            409,
            {
                "error": "Conflict",
                "message": e.message,
                "eventId": e.event_id,
                "status": 409,
            },
        )
    except Exception as e:
        # Check if it's a database connection error
        if _is_database_connection_error(e):
            logger.warning(f"{API_NAME} Database connection error detected: {e}")
            # Try to start the database
            start_response = await _try_start_database()
            if start_response:
                return start_response
            # If we couldn't start it or it's already starting, return user-friendly error
            return _create_response(
                503,
                {
                    "error": "Service Temporarily Unavailable",
                    "message": "Unable to connect to the database. The database may be starting. Please retry your request in a few moments.",
                    "status": 503,
                    "retry_after": 60,
                },
                headers={"Retry-After": "60"}
            )
        
        # Classify error for structured logging
        from service.retry_utils import classify_dsql_error
        is_retryable, error_type, sqlstate = classify_dsql_error(e)
        
        # Log with structured context
        log_context = {
            'error_type': error_type,
            'sqlstate': sqlstate,
            'is_retryable': is_retryable,
            'exception': str(e),
        }
        
        if error_type == 'OC000_TRANSACTION_CONFLICT':
            logger.error(
                f"{API_NAME} OC000 transaction conflict - all retries exhausted",
                extra=log_context,
                exc_info=True
            )
        else:
            logger.error(
                f"{API_NAME} Error processing event: {error_type}",
                extra=log_context,
                exc_info=True
            )
        
        return _create_response(
            500,
            {
                "error": f"Error processing event: {str(e)}",
                "error_type": error_type,
                "sqlstate": sqlstate,
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
    db_connection_error = False
    db_start_attempted = False
    
    try:
        service = await _initialize_service()
    except Exception as e:
        if _is_database_connection_error(e):
            logger.warning(f"{API_NAME} Database connection error during initialization: {e}")
            start_response = await _try_start_database()
            if start_response:
                return start_response
            return _create_response(
                503,
                {
                    "error": "Service Temporarily Unavailable",
                    "message": "Unable to connect to the database. The database may be starting. Please retry your request in a few moments.",
                    "status": 503,
                    "retry_after": 60,
                },
                headers={"Retry-After": "60"}
            )
        raise
    
    for event in events:
        try:
            # Validate event
            if not event.event_header.event_name:
                failed_count += 1
                continue
            
            if not event.event_body.entities:
                failed_count += 1
                continue
            
            # Validate entities (Pydantic models handle validation automatically)
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
        except DuplicateEventError as e:
            # Handle duplicate event ID (409 Conflict) - count as failed
            logger.warning(f"{API_NAME} Duplicate event ID in bulk: {e.event_id}")
            failed_count += 1
        except Exception as e:
            if _is_database_connection_error(e):
                logger.warning(f"{API_NAME} Database connection error processing event: {e}")
                db_connection_error = True
                # Try to start database on first connection error only
                if not db_start_attempted:
                    db_start_attempted = True
                    await _try_start_database()
            logger.error(f"{API_NAME} Error processing event in bulk: {e}", exc_info=True)
            failed_count += 1
    
    # If we had database connection errors, return appropriate message
    if db_connection_error and processed_count == 0:
        return _create_response(
            503,
            {
                "error": "Service Temporarily Unavailable",
                "message": "Unable to connect to the database. The database may be starting. Please retry your request in a few moments.",
                "status": 503,
                "retry_after": 60,
            },
            headers={"Retry-After": "60"}
        )
    
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


# Module-level dedicated event loop for Lambda handler
# This ensures we always use the same loop for asyncpg pool creation/usage
_lambda_loop: Optional[asyncio.AbstractEventLoop] = None


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for API Gateway HTTP API v2.
    
    Uses a deterministic single event loop strategy to ensure asyncpg pools
    are always created and used in the same loop context.
    """
    global _lambda_loop
    
    # Check if we're already in a running loop (shouldn't happen in real Lambda/SAM)
    try:
        running_loop = asyncio.get_running_loop()
        # This is unexpected for Lambda - fail fast with clear error
        logger.error(
            f"{API_NAME} CRITICAL: handler() called from within a running event loop. "
            f"Loop ID: {id(running_loop)}. This indicates a test harness or async caller issue. "
            f"For async callers, use _async_handler() directly instead of handler()."
        )
        raise RuntimeError(
            "Lambda handler cannot be called from within a running event loop. "
            "Use _async_handler() directly for async contexts, or fix the test harness."
        )
    except RuntimeError:
        # No running loop - this is the expected case for Lambda/SAM
        pass
    
    # Get or create the module-level dedicated loop
    if _lambda_loop is None or _lambda_loop.is_closed():
        _lambda_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(_lambda_loop)
        logger.info(f"{API_NAME} Created new dedicated event loop: {id(_lambda_loop)}")
    else:
        logger.debug(f"{API_NAME} Reusing existing event loop: {id(_lambda_loop)}")
    
    # Run the async handler in the dedicated loop
    try:
        return _lambda_loop.run_until_complete(_async_handler(event, context))
    except Exception as e:
        logger.error(f"{API_NAME} Error in handler: {e}", exc_info=True)
        raise


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
