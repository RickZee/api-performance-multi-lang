"""Generic entity repository for database operations."""

import asyncpg
import json
import logging
from typing import Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class EntityRepository:
    """Generic repository for entity database operations."""
    
    def __init__(self, pool: Optional[asyncpg.Pool], table_name: str):
        """Initialize repository (pool is optional, connections are passed directly)."""
        self.pool = pool  # Kept for backward compatibility, but not used
        self.table_name = table_name
    
    async def exists_by_entity_id(self, entity_id: str, conn: Optional[asyncpg.Connection] = None) -> bool:
        """Check if entity exists by entity ID.
        
        Args:
            entity_id: Entity ID to check
            conn: Optional database connection (for transactions). If not provided, acquires from pool.
        """
        import time
        step_start = time.time()
        
        if conn:
            try:
                exists = await conn.fetchval(
                    f"""
                    SELECT EXISTS(SELECT 1 FROM {self.table_name} WHERE entity_id = $1)
                    """,
                    entity_id,
                )
                duration = int((time.time() - step_start) * 1000)
                
                logger.debug(
                    f"Entity existence check completed",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'exists': exists,
                        'duration_ms': duration,
                    }
                )
                return exists
            except asyncpg.SerializationError as e:
                # OC000 transaction conflict
                duration = int((time.time() - step_start) * 1000)
                sqlstate = getattr(e, 'sqlstate', None)
                logger.warning(
                    f"OC000 transaction conflict during entity existence check",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'error_type': 'SerializationError',
                        'sqlstate': sqlstate,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    }
                )
                raise
            except Exception as e:
                duration = int((time.time() - step_start) * 1000)
                logger.error(
                    f"Error checking entity existence",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'error_type': type(e).__name__,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    },
                    exc_info=True
                )
                raise
        else:
            # Connection should always be provided by service layer
            # This fallback should not be reached in normal operation
            raise ValueError("Connection must be provided (no pool available)")
    
    async def create(self, entity_id: str, entity_type: str,
                     created_at: Optional[datetime], updated_at: Optional[datetime],
                     entity_data: dict, event_id: Optional[str] = None,
                     conn: Optional[asyncpg.Connection] = None) -> None:
        """Create a new entity.
        
        Args:
            entity_id: Entity ID
            entity_type: Entity type
            created_at: Created timestamp
            updated_at: Updated timestamp
            entity_data: Entity data as dict (will be stored as JSONB)
            event_id: Optional event ID (foreign key to event_headers.id)
            conn: Optional database connection (for transactions). If not provided, acquires from pool.
        """
        import time
        step_start = time.time()
        
        if conn:
            try:
                insert_start = time.time()
                await conn.execute(
                    f"""
                    INSERT INTO {self.table_name} (entity_id, entity_type, created_at, updated_at, entity_data, event_id)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    """,
                    entity_id,
                    entity_type,
                    created_at,
                    updated_at,
                    json.dumps(entity_data),
                    event_id,
                )
                insert_duration = int((time.time() - insert_start) * 1000)
                total_duration = int((time.time() - step_start) * 1000)
                
                logger.debug(
                    f"Entity created",
                    extra={
                        'entity_id': entity_id,
                        'entity_type': entity_type,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'insert_duration_ms': insert_duration,
                        'total_duration_ms': total_duration,
                    }
                )
            except asyncpg.SerializationError as e:
                # OC000 transaction conflict
                duration = int((time.time() - step_start) * 1000)
                sqlstate = getattr(e, 'sqlstate', None)
                logger.warning(
                    f"OC000 transaction conflict during entity create",
                    extra={
                        'entity_id': entity_id,
                        'entity_type': entity_type,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'error_type': 'SerializationError',
                        'sqlstate': sqlstate,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    }
                )
                raise
            except Exception as e:
                duration = int((time.time() - step_start) * 1000)
                logger.error(
                    f"Error creating entity",
                    extra={
                        'entity_id': entity_id,
                        'entity_type': entity_type,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'error_type': type(e).__name__,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    },
                    exc_info=True
                )
                raise
        else:
            # Connection should always be provided by service layer
            # This fallback should not be reached in normal operation
            raise ValueError("Connection must be provided (no pool available)")
    
    async def update(self, entity_id: str, updated_at: datetime, entity_data: dict,
                    event_id: Optional[str] = None, conn: Optional[asyncpg.Connection] = None) -> None:
        """Update an existing entity.
        
        Args:
            entity_id: Entity ID
            updated_at: Updated timestamp
            entity_data: Entity data as dict (will be stored as JSONB)
            event_id: Optional event ID (foreign key to event_headers.id) to track which event updated this entity
            conn: Optional database connection (for transactions). If not provided, acquires from pool.
        """
        import time
        step_start = time.time()
        
        if conn:
            try:
                update_start = time.time()
                result = await conn.execute(
                    f"""
                    UPDATE {self.table_name}
                    SET updated_at = $1, entity_data = $2, event_id = $3
                    WHERE entity_id = $4
                    """,
                    updated_at,
                    json.dumps(entity_data),
                    event_id,
                    entity_id,
                )
                update_duration = int((time.time() - update_start) * 1000)
                total_duration = int((time.time() - step_start) * 1000)
                
                # Extract rows affected from result (format: "UPDATE N")
                rows_affected = result.split()[-1] if result else "0"
                
                logger.debug(
                    f"Entity updated",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'rows_affected': rows_affected,
                        'update_duration_ms': update_duration,
                        'total_duration_ms': total_duration,
                    }
                )
            except asyncpg.SerializationError as e:
                # OC000 transaction conflict
                duration = int((time.time() - step_start) * 1000)
                sqlstate = getattr(e, 'sqlstate', None)
                logger.warning(
                    f"OC000 transaction conflict during entity update",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'error_type': 'SerializationError',
                        'sqlstate': sqlstate,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    }
                )
                raise
            except Exception as e:
                duration = int((time.time() - step_start) * 1000)
                logger.error(
                    f"Error updating entity",
                    extra={
                        'entity_id': entity_id,
                        'table_name': self.table_name,
                        'event_id': event_id,
                        'error_type': type(e).__name__,
                        'duration_ms': duration,
                        'error': str(e)[:200],
                    },
                    exc_info=True
                )
                raise
        else:
            # Connection should always be provided by service layer
            # This fallback should not be reached in normal operation
            raise ValueError("Connection must be provided (no pool available)")
