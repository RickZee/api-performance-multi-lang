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
from models.event import Event
from repository import BusinessEventRepository, get_connection_pool, DuplicateEventError, close_connection_pool
from service import EventProcessingService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - initialize and cleanup resources."""
    print("LIFESPAN: Starting lifespan context manager", flush=True)
    # #region agent log - Hypothesis F
    import json
    try:
        lifespan_startup_loop = asyncio.get_running_loop()
        print(f"LIFESPAN: Got loop {id(lifespan_startup_loop)}", flush=True)
        with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
            f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"F,G,H,I","location":"app.py:lifespan","message":"Lifespan startup - entering","data":{"loop_id":id(lifespan_startup_loop),"loop_type":type(lifespan_startup_loop).__name__},"timestamp":int(__import__('time').time()*1000)})+'\n')
        print("LIFESPAN: Instrumentation written", flush=True)
    except Exception as e:
        print(f"LIFESPAN: Error in instrumentation: {e}", flush=True)
        try:
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"ERROR","location":"app.py:lifespan","message":"Lifespan startup instrumentation error","data":{"error":str(e)},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except Exception as e2:
            print(f"LIFESPAN: Failed to write error log: {e2}", flush=True)
    # #endregion

    # Startup: Initialize service and connection pool in the application's event loop
    global _service
    try:
        # Get current event loop to verify we're in the right context
        startup_loop = asyncio.get_running_loop()
        logger.info(f"{API_NAME} Lifespan startup - event loop: {id(startup_loop)}")

        # #region agent log - Hypothesis F
        try:
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"F","location":"app.py:lifespan","message":"Before get_service call","data":{"loop_id":id(startup_loop)},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion

        _service = await get_service()

        # Store service in app.state for access
        app.state.service = _service

        # Verify pool is bound to the same loop
        if hasattr(_service.pool, '_loop'):
            pool_loop_id = id(_service.pool._loop)
            logger.info(f"{API_NAME} Service initialized - pool loop: {pool_loop_id}, startup loop: {id(startup_loop)}")
            if pool_loop_id != id(startup_loop):
                logger.error(f"{API_NAME} WARNING: Pool loop mismatch at startup!")
                # #region agent log - Hypothesis F
                try:
                    with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                        f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"F","location":"app.py:lifespan","message":"POOL LOOP MISMATCH DETECTED","data":{"startup_loop_id":id(startup_loop),"pool_loop_id":pool_loop_id},"timestamp":int(__import__('time').time()*1000)})+'\n')
                except: pass
                # #endregion

        logger.info(f"{API_NAME} Service initialized on startup")
        # #region agent log - Hypothesis F
        try:
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"F","location":"app.py:lifespan","message":"Lifespan startup complete","data":{"loop_id":id(startup_loop)},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion
    except Exception as e:
        logger.error(f"{API_NAME} Failed to initialize service on startup: {e}", exc_info=True)
        raise

    yield

    # Shutdown: Clean up resources
    # #region agent log - Hypothesis F
    try:
        lifespan_shutdown_loop = asyncio.get_running_loop()
        with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
            f.write(json.dumps({"sessionId":"debug-session","runId":"run2","hypothesisId":"F","location":"app.py:lifespan","message":"Lifespan shutdown - entering","data":{"loop_id":id(lifespan_shutdown_loop)},"timestamp":int(__import__('time').time()*1000)})+'\n')
    except: pass
    # #endregion

    if _service is not None and _service.pool is not None:
        try:
            await _service.pool.close()
            logger.info(f"{API_NAME} Connection pool closed")
        except Exception as e:
            logger.warning(f"{API_NAME} Error closing connection pool: {e}")
        _service = None
    await close_connection_pool()


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
    
    # #region agent log
    import json
    try:
        current_loop = asyncio.get_running_loop()
        loop_id = id(current_loop)
        with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
            f.write(json.dumps({"sessionId":"debug-session","runId":"run1","hypothesisId":"A,B,C","location":"app.py:41","message":"get_service entry","data":{"loop_id":loop_id,"has_service":_service is not None},"timestamp":int(__import__('time').time()*1000)})+'\n')
    except: pass
    # #endregion
    
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
        # #region agent log
        try:
            loop_before_pool = asyncio.get_running_loop()
            loop_id_before_pool = id(loop_before_pool)
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run1","hypothesisId":"A,B","location":"app.py:57","message":"BEFORE get_connection_pool","data":{"loop_id":loop_id_before_pool},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion
        pool = await get_connection_pool(_config.database_url)
        # #region agent log
        try:
            loop_after_pool = asyncio.get_running_loop()
            loop_id_after_pool = id(loop_after_pool)
            with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
                f.write(json.dumps({"sessionId":"debug-session","runId":"run1","hypothesisId":"A,B","location":"app.py:58","message":"AFTER get_connection_pool","data":{"loop_id":loop_id_after_pool,"pool_id":id(pool)},"timestamp":int(__import__('time').time()*1000)})+'\n')
        except: pass
        # #endregion
        
        # Initialize repositories and service
        business_event_repo = BusinessEventRepository(pool)
        _service = EventProcessingService(business_event_repo, pool)
        
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
    
    # Validate each entity
    for entity in event.event_body.entities:
        if not entity.entity_type:
            raise HTTPException(status_code=422, detail="Entity type cannot be empty")
        if not entity.entity_id:
            raise HTTPException(status_code=422, detail="Entity ID cannot be empty")
    
    logger.info(f"{API_NAME} Received event: {event.event_header.event_name}")
    
    # #region agent log
    import json
    try:
        current_loop = asyncio.get_running_loop()
        loop_id = id(current_loop)
        with open('/Users/rickzakharov/dev/github/api-performance-multi-lang/.cursor/debug.log', 'a') as f:
            f.write(json.dumps({"sessionId":"debug-session","runId":"run1","hypothesisId":"A,C","location":"app.py:107","message":"process_event handler entry","data":{"loop_id":loop_id,"event_name":event.event_header.event_name},"timestamp":int(__import__('time').time()*1000)})+'\n')
    except: pass
    # #endregion
    
    # Process event
    try:
        # Get service (should already be initialized from lifespan)
        service = await get_service()
        
        # Verify we're in the correct event loop
        request_loop = asyncio.get_running_loop()
        if hasattr(service.pool, '_loop'):
            pool_loop = service.pool._loop
            if pool_loop is not request_loop:
                logger.error(f"{API_NAME} CRITICAL: Event loop mismatch! Pool: {id(pool_loop)}, Request: {id(request_loop)}")
                raise RuntimeError(f"Pool created in loop {id(pool_loop)} but used in loop {id(request_loop)}")
            else:
                logger.debug(f"{API_NAME} Event loop verified: {id(request_loop)}")
        
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
            
            # Validate entities
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
