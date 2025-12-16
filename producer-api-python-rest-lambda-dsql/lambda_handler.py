"""Lambda handler for Producer API Python REST."""

import asyncio
import json
import logging
from typing import Any, Dict, Optional
from datetime import datetime

import sys
import os
import boto3
import time
from botocore.exceptions import ClientError

# Add the package directory to the path for Lambda
sys.path.insert(0, os.path.dirname(__file__))

from config import load_lambda_config
from constants import API_NAME
from producer_api_python_rest_lambda_shared.models import Event
from producer_api_python_rest_lambda_shared.repository import BusinessEventRepository
from producer_api_python_rest_lambda_shared.exceptions import DuplicateEventError
from producer_api_python_rest_lambda_shared.service import EventProcessingService
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
    """Handle health check request with database connectivity test."""
    try:
        # Test database connectivity
        service = await _initialize_service()
        # Quick connection test using a simple query
        conn = await service.connection_factory()
        try:
            await conn.execute("SELECT 1")
            # Close direct connection (DSQL uses direct connections)
            await conn.close()
        except Exception as close_error:
            logger.warning(f"{API_NAME} Error closing health check connection: {close_error}")
        
        return _create_response(
            200,
            {
                "status": "healthy",
                "message": "Producer API is healthy",
                "database": "connected",
            },
        )
    except Exception as e:
        logger.error(f"{API_NAME} Health check failed: {e}")
        return _create_response(
            503,
            {
                "status": "unhealthy",
                "message": "Database connection failed",
                "error": str(e),
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
        # Invoke the auto-start Lambda with timeout handling
        import asyncio
        
        # Use asyncio timeout to prevent hanging
        timeout_seconds = float(os.getenv('AUTO_START_TIMEOUT', '5.0'))
        
        try:
            # Run Lambda invocation with timeout (boto3 is sync, so use to_thread)
            response = await asyncio.wait_for(
                asyncio.to_thread(
                    _lambda_client.invoke,
                    FunctionName=auto_start_function,
                    InvocationType='RequestResponse'
                ),
                timeout=timeout_seconds
            )
        except asyncio.TimeoutError:
            logger.warning(f"{API_NAME} Auto-start Lambda invocation timed out after {timeout_seconds}s")
            return None
        
        # Check response status
        if response.get('StatusCode') != 200:
            logger.warning(f"{API_NAME} Auto-start Lambda returned non-200 status: {response.get('StatusCode')}")
            return None
        
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
    except asyncio.TimeoutError:
        logger.warning(f"{API_NAME} Auto-start Lambda invocation timed out")
        return None
    except ClientError as e:
        logger.warning(f"{API_NAME} Failed to invoke auto-start Lambda: {e}")
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
    logger.info(f"{API_NAME} _handle_process_event called, parsing JSON...")
    try:
        # Parse request body
        logger.info(f"{API_NAME} Parsing event_body (length: {len(event_body)})")
        event_data = json.loads(event_body)
        logger.info(f"{API_NAME} JSON parsed, creating Event object...")
        event = Event(**event_data)
        logger.info(f"{API_NAME} Event object created successfully")
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
    
    event_id = event.event_header.uuid or "unknown"
    event_type = event.event_header.event_type or "unknown"
    event_name = event.event_header.event_name or "unknown"
    
    logger.info(
        f"{API_NAME} Received event: {event_name}",
        extra={
            'event_id': event_id,
            'event_type': event_type,
            'event_name': event_name,
            'entity_count': len(event.event_body.entities) if event.event_body.entities else 0,
            'entity_types': [e.entity_type for e in event.event_body.entities] if event.event_body.entities else [],
        }
    )
    
    # Process event
    try:
        logger.info(f"{API_NAME} Initializing service...")
        service = await _initialize_service()
        logger.info(f"{API_NAME} Service initialized, starting event processing...")
        start_time = time.time()
        
        logger.info(
            f"{API_NAME} Starting event processing",
            extra={
                'event_id': event_id,
                'event_type': event_type,
                'timestamp': start_time,
            }
        )
        
        logger.info(f"{API_NAME} Calling service.process_event...")
        await service.process_event(event)
        logger.info(f"{API_NAME} service.process_event completed")
        duration_ms = int((time.time() - start_time) * 1000)
        
        logger.info(
            f"{API_NAME} Event processed successfully in {duration_ms}ms",
            extra={
                'event_id': event_id,
                'event_type': event_type,
                'duration_ms': duration_ms,
            }
        )
        
        # Emit CloudWatch metric (non-blocking)
        try:
            cloudwatch = boto3.client('cloudwatch', region_name=os.getenv('AWS_REGION', 'us-east-1'))
            cloudwatch.put_metric_data(
                Namespace='ProducerAPI',
                MetricData=[{
                    'MetricName': 'EventProcessingDuration',
                    'Value': duration_ms,
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {'Name': 'API', 'Value': 'PythonREST-DSQL'},
                        {'Name': 'EventName', 'Value': event.event_header.event_name or 'unknown'}
                    ]
                }]
            )
        except Exception as e:
            logger.debug(f"Failed to emit CloudWatch metric: {e}")
        
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
    # Check bulk event size limit
    MAX_BULK_EVENTS = int(os.getenv('MAX_BULK_EVENTS', '100'))
    
    try:
        events_data = json.loads(event_body)
        
        # Validate array size before processing
        if len(events_data) > MAX_BULK_EVENTS:
            return _create_response(
                400,
                {
                    "error": "Too many events",
                    "message": f"Maximum {MAX_BULK_EVENTS} events allowed per request",
                    "received": len(events_data),
                    "status": 400,
                },
            )
        
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
    
    bulk_start_time = time.time()
    logger.info(
        f"{API_NAME} Received bulk request with {len(events)} events",
        extra={
            'bulk_event_count': len(events),
            'bulk_start_timestamp_utc': datetime.utcnow().isoformat() + 'Z',
        }
    )
    
    processed_count = 0
    failed_count = 0
    conflict_count = 0
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
    
    for idx, event in enumerate(events):
        event_start_time = time.time()
        event_id = event.event_header.uuid or f"bulk-event-{idx}"
        event_type = event.event_header.event_type or "unknown"
        
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
            event_duration = int((time.time() - event_start_time) * 1000)
            
            logger.debug(
                f"{API_NAME} Bulk event {idx+1}/{len(events)} processed successfully",
                extra={
                    'bulk_index': idx,
                    'event_id': event_id,
                    'event_type': event_type,
                    'duration_ms': event_duration,
                    'cumulative_success': processed_count,
                    'cumulative_failed': failed_count,
                }
            )
        except DuplicateEventError as e:
            # Handle duplicate event ID (409 Conflict) - count as failed
            conflict_count += 1
            failed_count += 1
            event_duration = int((time.time() - event_start_time) * 1000)
            logger.warning(
                f"{API_NAME} Duplicate event ID in bulk: {e.event_id}",
                extra={
                    'bulk_index': idx,
                    'event_id': event_id,
                    'event_type': event_type,
                    'duration_ms': event_duration,
                    'error_type': 'DUPLICATE_EVENT',
                    'cumulative_conflicts': conflict_count,
                }
            )
        except Exception as e:
            if _is_database_connection_error(e):
                logger.warning(f"{API_NAME} Database connection error processing event: {e}")
                db_connection_error = True
                # Try to start database on first connection error only
                if not db_start_attempted:
                    db_start_attempted = True
                    await _try_start_database()
            event_duration = int((time.time() - event_start_time) * 1000)
            logger.error(
                f"{API_NAME} Error processing event in bulk: {e}",
                extra={
                    'bulk_index': idx,
                    'event_id': event_id,
                    'event_type': event_type,
                    'duration_ms': event_duration,
                    'error_type': type(e).__name__,
                },
                exc_info=True
            )
            failed_count += 1
    
    bulk_duration = int((time.time() - bulk_start_time) * 1000)
    logger.info(
        f"{API_NAME} Bulk processing complete",
        extra={
            'total_events': len(events),
            'success_count': processed_count,
            'failure_count': failed_count,
            'conflict_count': conflict_count,
            'total_duration_ms': bulk_duration,
            'avg_duration_ms': int(bulk_duration / len(events)) if events else 0,
            'success_rate': f"{(processed_count / len(events) * 100):.1f}%" if events else "0%",
            'bulk_end_timestamp_utc': datetime.utcnow().isoformat() + 'Z',
        }
    )
    
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
    logger.info(f"{API_NAME} handler() called - START")
    
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
        logger.info(f"{API_NAME} About to run async handler in event loop")
        result = _lambda_loop.run_until_complete(_async_handler(event, context))
        logger.info(f"{API_NAME} Async handler completed successfully")
        return result
    except Exception as e:
        logger.error(f"{API_NAME} Error in handler: {e}", exc_info=True)
        raise


async def _async_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Async handler implementation."""
    logger.info(f"{API_NAME} _async_handler called")
    # Extract path and method
    request_context = event.get("requestContext", {})
    http_context = request_context.get("http", {})
    path = http_context.get("path", "")
    method = http_context.get("method", "")
    logger.info(f"{API_NAME} Path: {path}, Method: {method}")
    
    # Extract request ID for correlation
    request_id = request_context.get("requestId", context.aws_request_id if context else "unknown")
    
    # Log with structured context
    logger.info(
        f"{API_NAME} Lambda request",
        extra={
            "request_id": request_id,
            "method": method,
            "path": path,
        }
    )
    
    # Route requests
    logger.info(f"{API_NAME} Routing request to path: {path}")
    if path == "/api/v1/events/health" and method == "GET":
        logger.info(f"{API_NAME} Routing to health check")
        return await _handle_health_check()
    elif path == "/api/v1/events" and method == "POST":
        logger.info(f"{API_NAME} Routing to process event")
        body = event.get("body", "{}")
        logger.info(f"{API_NAME} Body length: {len(body)}")
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
