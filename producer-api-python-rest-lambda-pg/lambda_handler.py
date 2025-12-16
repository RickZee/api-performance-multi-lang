"""Lambda handler for Producer API Python REST."""

import asyncio
import json
import logging
from typing import Any, Dict, Optional

import sys
import os
import boto3
import time
from botocore.exceptions import ClientError

# Configure logging FIRST before any other imports
# This ensures we can log errors even if imports fail
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Add the package directory to the path for Lambda
sys.path.insert(0, os.path.dirname(__file__))

from config import load_lambda_config
from constants import API_NAME
from producer_api_python_rest_lambda_shared.models import Event
from producer_api_python_rest_lambda_shared.repository import BusinessEventRepository
from producer_api_python_rest_lambda_shared.exceptions import DuplicateEventError
from producer_api_python_rest_lambda_shared.service import EventProcessingService
from repository import get_connection

# Global service instance (reused across invocations)
_service: EventProcessingService | None = None
_config = None

# Removed module-level event loop - using asyncio.run() per invocation instead
_lambda_client = None

# Track import errors (for error handling in handler)
_import_error: Optional[Exception] = None


async def _initialize_service():
    """Initialize service with direct connections (no pooling).
    
    RDS Proxy handles connection pooling at the infrastructure level,
    so we use direct connections per request to avoid redundant pooling.
    
    Creates a fresh connection factory that uses the current event loop context,
    preventing loop mismatch issues.
    """
    global _service, _config, _lambda_client
    
    # Get current event loop ID for logging
    try:
        current_loop = asyncio.get_running_loop()
        loop_id = id(current_loop)
        logger.debug(f"{API_NAME} Initializing service in event loop: {loop_id}")
    except RuntimeError:
        loop_id = "unknown"
        logger.warning(f"{API_NAME} No running event loop detected during service initialization")
    
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
        
        # Create connection factory that uses current event loop context
        # This factory will be called later, ensuring it uses the same loop
        # RDS Proxy handles pooling at infrastructure level
        async def connection_factory():
            # Verify we're in the same loop context
            try:
                factory_loop = asyncio.get_running_loop()
                factory_loop_id = id(factory_loop)
                logger.debug(f"{API_NAME} Connection factory called in event loop: {factory_loop_id}")
                if loop_id != "unknown" and factory_loop_id != loop_id:
                    logger.warning(f"{API_NAME} Loop ID changed: init={loop_id}, factory={factory_loop_id}")
            except RuntimeError:
                logger.warning(f"{API_NAME} No running loop in connection factory")
            
            return await get_connection(_config)
        
        _service = EventProcessingService(
            business_event_repo=business_event_repo,
            connection_factory=connection_factory,
            api_name=API_NAME,
            should_close_connection=True  # Close direct connections after use
        )
        
        logger.info(f"{API_NAME} Lambda handler initialized (using direct connections, RDS Proxy handles pooling, loop_id={loop_id})")
    
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
        # Test database connectivity with a direct connection
        service = await _initialize_service()
        # Quick connection test using a simple query
        conn = await service.connection_factory()
        try:
            await conn.execute("SELECT 1")
        finally:
            # Close direct connection
            await conn.close()
        
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
        from botocore.exceptions import ClientError
        
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
    """Handle single event processing with detailed lifecycle tracking."""
    lifecycle_start = time.time()
    lifecycle_stages = {}
    
    stage_start = time.time()
    logger.info(f"{API_NAME} [LIFECYCLE] Event processing started")
    lifecycle_stages['request_received'] = {'timestamp': stage_start, 'duration_ms': 0}
    
    try:
        # Parse request body
        stage_start = time.time()
        logger.info(f"{API_NAME} [LIFECYCLE] Parsing JSON (body length: {len(event_body)})")
        event_data = json.loads(event_body)
        lifecycle_stages['json_parsed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000)
        }
        
        # Create Event object
        stage_start = time.time()
        logger.info(f"{API_NAME} [LIFECYCLE] Creating Event object from parsed data")
        event = Event(**event_data)
        lifecycle_stages['event_created'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000)
        }
        logger.info(f"{API_NAME} [LIFECYCLE] Event object created successfully")
    except json.JSONDecodeError as e:
        lifecycle_stages['json_parse_failed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - lifecycle_start) * 1000),
            'error': str(e)
        }
        logger.error(f"{API_NAME} [LIFECYCLE] JSON parse failed: {e}", exc_info=True)
        return _create_response(
            400,
            {
                "error": "Invalid JSON",
                "status": 400,
                "lifecycle": lifecycle_stages,
            },
        )
    except Exception as e:
        lifecycle_stages['event_creation_failed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - lifecycle_start) * 1000),
            'error': str(e)
        }
        logger.error(f"{API_NAME} [LIFECYCLE] Event creation failed: {e}", exc_info=True)
        return _create_response(
            422,
            {
                "error": f"Invalid event structure: {str(e)}",
                "status": 422,
                "lifecycle": lifecycle_stages,
            },
        )
    
    # Validate event
    stage_start = time.time()
    logger.info(f"{API_NAME} [LIFECYCLE] Starting event validation")
    
    event_id = event.event_header.uuid or "unknown"
    event_type = event.event_header.event_type or "unknown"
    event_name = event.event_header.event_name or "unknown"
    
    if not event.event_header.event_name:
        lifecycle_stages['validation_failed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000),
            'error': 'Event header event_name is required'
        }
        logger.warning(f"{API_NAME} [LIFECYCLE] Validation failed: missing event_name")
        return _create_response(
            422,
            {
                "error": "Event header event_name is required",
                "status": 422,
                "lifecycle": lifecycle_stages,
            },
        )
    
    if not event.entities:
        lifecycle_stages['validation_failed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000),
            'error': 'Event must contain at least one entity'
        }
        logger.warning(f"{API_NAME} [LIFECYCLE] Validation failed: no entities")
        return _create_response(
            422,
            {
                "error": "Event must contain at least one entity",
                "status": 422,
                "lifecycle": lifecycle_stages,
            },
        )
    
    # Validate each entity
    for idx, entity in enumerate(event.entities):
        if not entity.entity_header.entity_type:
            lifecycle_stages['validation_failed'] = {
                'timestamp': time.time(),
                'duration_ms': int((time.time() - stage_start) * 1000),
                'error': f'Entity {idx} missing entity_type'
            }
            logger.warning(f"{API_NAME} [LIFECYCLE] Validation failed: entity {idx} missing type")
            return _create_response(
                422,
                {
                    "error": "Entity type cannot be empty",
                    "status": 422,
                    "lifecycle": lifecycle_stages,
                },
            )
        if not entity.entity_header.entity_id:
            lifecycle_stages['validation_failed'] = {
                'timestamp': time.time(),
                'duration_ms': int((time.time() - stage_start) * 1000),
                'error': f'Entity {idx} missing entity_id'
            }
            logger.warning(f"{API_NAME} [LIFECYCLE] Validation failed: entity {idx} missing id")
            return _create_response(
                422,
                {
                    "error": "Entity ID cannot be empty",
                    "status": 422,
                    "lifecycle": lifecycle_stages,
                },
            )
    
    lifecycle_stages['validation_passed'] = {
        'timestamp': time.time(),
        'duration_ms': int((time.time() - stage_start) * 1000)
    }
    
    logger.info(
        f"{API_NAME} [LIFECYCLE] Event validated: {event_name}",
        extra={
            'event_id': event_id,
            'event_type': event_type,
            'event_name': event_name,
            'entity_count': len(event.entities) if event.entities else 0,
            'entity_types': [e.entity_header.entity_type for e in event.entities] if event.entities else [],
        }
    )
    
    # Process event
    stage_start = time.time()
    logger.info(f"{API_NAME} [LIFECYCLE] Initializing service")
    try:
        service = await _initialize_service()
        lifecycle_stages['service_initialized'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000)
        }
        logger.info(f"{API_NAME} [LIFECYCLE] Service initialized in {lifecycle_stages['service_initialized']['duration_ms']}ms")
        
        # Process event
        stage_start = time.time()
        logger.info(f"{API_NAME} [LIFECYCLE] Processing event in service layer (event_id: {event_id})")
        
        # Log event loop ID before processing
        try:
            process_loop = asyncio.get_running_loop()
            process_loop_id = id(process_loop)
            logger.debug(f"{API_NAME} [LIFECYCLE] About to process event in loop: {process_loop_id}")
        except RuntimeError:
            process_loop_id = "unknown"
        
        await service.process_event(event)
        lifecycle_stages['event_processed'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - stage_start) * 1000)
        }
        
        total_duration_ms = int((time.time() - lifecycle_start) * 1000)
        lifecycle_stages['total_duration_ms'] = total_duration_ms
        
        logger.info(
            f"{API_NAME} [LIFECYCLE] Event processed successfully",
            extra={
                'event_id': event_id,
                'event_type': event_type,
                'event_name': event_name,
                'total_duration_ms': total_duration_ms,
                'lifecycle_stages': lifecycle_stages,
            }
        )
        
        # CloudWatch metrics removed - synchronous put_metric_data() was blocking execution
        # Metrics can be extracted from CloudWatch Logs using Logs Insights queries
        # This eliminates blocking operations from the request path
        
        return _create_response(
            200,
            {
                "success": True,
                "message": "Event processed successfully",
                "event_id": event_id,
                "lifecycle": lifecycle_stages,
            },
        )
    except DuplicateEventError as e:
        lifecycle_stages['duplicate_event'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - lifecycle_start) * 1000),
            'error': str(e),
            'event_id': e.event_id
        }
        logger.warning(f"{API_NAME} [LIFECYCLE] Duplicate event detected: {e.event_id}")
        return _create_response(
            409,
            {
                "error": "Conflict",
                "message": e.message,
                "eventId": e.event_id,
                "status": 409,
                "lifecycle": lifecycle_stages,
            },
        )
    except Exception as e:
        lifecycle_stages['processing_error'] = {
            'timestamp': time.time(),
            'duration_ms': int((time.time() - lifecycle_start) * 1000),
            'error': str(e),
            'error_type': type(e).__name__
        }
        logger.error(f"{API_NAME} [LIFECYCLE] Error processing event: {e}", exc_info=True)
        
        # Check if it's a database connection error
        if _is_database_connection_error(e):
            logger.warning(f"{API_NAME} [LIFECYCLE] Database connection error detected: {e}")
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
                    "lifecycle": lifecycle_stages,
                },
                headers={"Retry-After": "60"}
            )
        
        return _create_response(
            500,
            {
                "error": f"Error processing event: {str(e)}",
                "status": 500,
                "lifecycle": lifecycle_stages,
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
            
            if not event.entities:
                failed_count += 1
                continue
            
            # Validate entities (Pydantic models handle validation automatically)
            valid = True
            for entity in event.entities:
                if not entity.entity_header.entity_type or not entity.entity_header.entity_id:
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


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for API Gateway HTTP API v2.
    
    Uses asyncio.run() to create a fresh event loop per invocation.
    This ensures asyncpg connections are created and used in the same loop context,
    preventing connection hangs due to loop mismatches.
    """
    global _import_error
    
    # Check for import errors first
    if _import_error is not None:
        logger.error(f"Handler called but imports failed: {_import_error}", exc_info=True)
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "error": "Internal Server Error",
                "message": f"Module import failed: {str(_import_error)}",
                "status": 500,
            }),
        }
    
    try:
        # Use asyncio.run() to create a fresh event loop per invocation
        # This ensures all async operations (including asyncpg connections) 
        # are created and used in the same loop context
        return asyncio.run(_async_handler(event, context))
    except Exception as e:
        # Log to CloudWatch before returning error response
        logger.error(f"{API_NAME} Handler initialization or execution failed: {e}", exc_info=True)
        # Return proper error response instead of raising
        return _create_response(
            500,
            {
                "error": "Internal Server Error",
                "message": "An error occurred processing the request",
                "status": 500,
            },
        )


async def _async_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Async handler implementation."""
    try:
        # Log event loop ID for debugging
        try:
            handler_loop = asyncio.get_running_loop()
            handler_loop_id = id(handler_loop)
            logger.debug(f"{API_NAME} Async handler running in event loop: {handler_loop_id}")
        except RuntimeError:
            handler_loop_id = "unknown"
            logger.warning(f"{API_NAME} No running loop detected in async handler")
        
        # Extract path and method
        request_context = event.get("requestContext", {})
        http_context = request_context.get("http", {})
        path = http_context.get("path", "")
        method = http_context.get("method", "")
        
        # Extract request ID for correlation
        # LambdaContext uses 'aws_request_id', not 'request_id'
        request_id = request_context.get("requestId", context.aws_request_id if context else "unknown")
        
        # Log with structured context including loop ID
        logger.info(
            f"{API_NAME} Lambda request",
            extra={
                "request_id": request_id,
                "method": method,
                "path": path,
                "loop_id": handler_loop_id,
            }
        )
        
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
    except Exception as e:
        logger.error(f"{API_NAME} Error in async handler: {e}", exc_info=True)
        return _create_response(
            500,
            {
                "error": "Internal Server Error",
                "message": "An error occurred processing the request",
                "status": 500,
            },
        )
