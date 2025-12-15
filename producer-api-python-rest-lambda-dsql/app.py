"""FastAPI application wrapper for the Lambda handler."""

import asyncio
import json
import logging
import os
from typing import List

from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - initialize and cleanup resources."""
    # Startup: Initialize service and connection pool in the application's event loop
    global _service
    try:
        # Get current event loop to verify we're in the right context
        startup_loop = asyncio.get_running_loop()
        logger.info(f"{API_NAME} Lifespan startup - event loop: {id(startup_loop)}")

        _service = await get_service()

        # Store service in app.state for access
        app.state.service = _service

        logger.info(f"{API_NAME} Service initialized on startup (using direct connections)")
    except Exception as e:
        logger.error(f"{API_NAME} Failed to initialize service on startup: {e}", exc_info=True)
        raise

    yield

    # Shutdown: Clean up resources
    # No pool to close (using direct connections)
    _service = None
    logger.info(f"{API_NAME} Service cleaned up")


app = FastAPI(title=API_NAME, version="1.0.0", lifespan=lifespan)

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global service instance - will be initialized on first request
_service: EventProcessingService | None = None


async def get_service() -> EventProcessingService:
    """Get or initialize service with connection pool (singleton pattern)."""
    global _service
    
    if _service is None:
        _config = load_lambda_config()
        
        # Set log level from config
        if _config.log_level == "debug":
            logging.getLogger().setLevel(logging.DEBUG)
        elif _config.log_level == "warn":
            logging.getLogger().setLevel(logging.WARNING)
        elif _config.log_level == "error":
            logging.getLogger().setLevel(logging.ERROR)
        
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
        
        logger.info(f"{API_NAME} FastAPI app initialized")
    
    return _service




@app.get("/api/v1/events/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "message": "Producer API is healthy",
    }


@app.post("/api/v1/events")
async def process_event(event: Event):
    """Handle single event processing."""
    # Validate event
    if not event.event_header.event_name:
        raise HTTPException(status_code=422, detail="Event header event_name is required")
    
    if not event.event_body.entities:
        raise HTTPException(status_code=422, detail="Event body must contain at least one entity")
    
    # Validate each entity (Pydantic models handle validation automatically)
    for entity in event.event_body.entities:
        if not entity.entity_type:
            raise HTTPException(status_code=422, detail="Entity type cannot be empty")
        if not entity.entity_id:
            raise HTTPException(status_code=422, detail="Entity ID cannot be empty")
    
    logger.info(f"{API_NAME} Received event: {event.event_header.event_name}")
    
    # Process event
    try:
        # Get service (should already be initialized from lifespan)
        service = await get_service()
        
        await service.process_event(event)
        
        return {
            "success": True,
            "message": "Event processed successfully",
        }
    except DuplicateEventError as e:
        logger.warning(f"{API_NAME} Duplicate event ID: {e.event_id}")
        raise HTTPException(
            status_code=409,
            detail={
                "error": "Conflict",
                "message": e.message,
                "eventId": e.event_id,
            }
        )
    except Exception as e:
        logger.error(f"{API_NAME} Error processing event: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error processing event: {str(e)}")


@app.post("/api/v1/events/bulk")
async def process_bulk_events(events: List[Event]):
    """Handle bulk event processing."""
    if not events:
        raise HTTPException(status_code=422, detail="Invalid request: events list is null or empty")
    
    logger.info(f"{API_NAME} Received bulk request with {len(events)} events")
    
    processed_count = 0
    failed_count = 0
    errors = []
    
    try:
        service = await get_service()
    except Exception as e:
        logger.error(f"{API_NAME} Error initializing service: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error initializing service: {str(e)}")
    
    for idx, event in enumerate(events):
        try:
            # Validate event
            if not event.event_header.event_name:
                failed_count += 1
                errors.append(f"Event {idx}: event_name is required")
                continue
            
            if not event.event_body.entities:
                failed_count += 1
                errors.append(f"Event {idx}: must contain at least one entity")
                continue
            
            # Validate entities (Pydantic models handle validation automatically)
            valid = True
            for entity in event.event_body.entities:
                if not entity.entity_type or not entity.entity_id:
                    valid = False
                    break
            
            if not valid:
                failed_count += 1
                errors.append(f"Event {idx}: entity type and ID are required")
                continue
            
            await service.process_event(event)
            processed_count += 1
        except DuplicateEventError as e:
            logger.warning(f"{API_NAME} Duplicate event ID in bulk: {e.event_id}")
            failed_count += 1
            errors.append(f"Event {idx}: duplicate event ID {e.event_id}")
        except Exception as e:
            logger.error(f"{API_NAME} Error processing event {idx} in bulk: {e}", exc_info=True)
            failed_count += 1
            errors.append(f"Event {idx}: {str(e)}")
    
    return {
        "success": True,
        "message": f"Processed {processed_count} events, {failed_count} failed",
        "processed": processed_count,
        "failed": failed_count,
        "total": len(events),
        "errors": errors[:10] if errors else [],  # Limit errors to first 10
    }


if __name__ == "__main__":
    import uvicorn

    # Ensure the database URL is set for local execution
    os.environ["DATABASE_URL"] = os.getenv("DATABASE_URL", "postgresql://postgres:password@host.docker.internal:5432/car_dealership")
    os.environ["LOG_LEVEL"] = os.getenv("LOG_LEVEL", "info")

    # Force asyncio loop to avoid uvloop issues
    import asyncio
    asyncio.set_event_loop_policy(asyncio.DefaultEventLoopPolicy())

    # Run FastAPI app with uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=int(os.getenv("FLASK_PORT", 8080)),
        log_level="info",
        reload=False,
        loop="asyncio",  # Explicitly set asyncio loop
    )
