"""Generic entity repository for database operations."""

import asyncpg
import json
import logging
from typing import Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class EntityRepository:
    """Generic repository for entity database operations."""
    
    def __init__(self, table_name: str):
        """Initialize repository.
        
        Args:
            table_name: Name of the entity table
        """
        self.table_name = table_name
    
    async def exists_by_entity_id(self, entity_id: str, conn: asyncpg.Connection) -> bool:
        """Check if entity exists by entity ID.
        
        Args:
            entity_id: Entity ID to check
            conn: Database connection (required)
        """
        exists = await conn.fetchval(
            f"""
            SELECT EXISTS(SELECT 1 FROM {self.table_name} WHERE entity_id = $1)
            """,
            entity_id,
        )
        return exists
    
    async def create(self, entity_id: str, entity_type: str,
                     created_at: Optional[datetime], updated_at: Optional[datetime],
                     entity_data: dict, event_id: Optional[str] = None,
                     conn: asyncpg.Connection = None) -> None:
        """Create a new entity.
        
        Args:
            entity_id: Entity ID
            entity_type: Entity type
            created_at: Created timestamp
            updated_at: Updated timestamp
            entity_data: Entity data as dict (will be stored as JSONB)
            event_id: Optional event ID (foreign key to event_headers.id)
            conn: Database connection (required)
        """
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
    
    async def update(self, entity_id: str, updated_at: datetime, entity_data: dict,
                    event_id: Optional[str] = None, conn: asyncpg.Connection = None) -> None:
        """Update an existing entity.
        
        Args:
            entity_id: Entity ID
            updated_at: Updated timestamp
            entity_data: Entity data as dict (will be stored as JSONB)
            event_id: Optional event ID (foreign key to event_headers.id) to track which event updated this entity
            conn: Database connection (required)
        """
        await conn.execute(
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
