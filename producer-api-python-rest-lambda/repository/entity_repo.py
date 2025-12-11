"""Generic entity repository for database operations."""

import asyncpg
import json
import logging
from typing import Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class EntityRepository:
    """Generic repository for entity database operations."""
    
    def __init__(self, pool: asyncpg.Pool, table_name: str):
        """Initialize repository with connection pool and table name."""
        self.pool = pool
        self.table_name = table_name
    
    async def exists_by_entity_id(self, entity_id: str) -> bool:
        """Check if entity exists by entity ID."""
        async with self.pool.acquire() as conn:
            exists = await conn.fetchval(
                f"""
                SELECT EXISTS(SELECT 1 FROM {self.table_name} WHERE entity_id = $1)
                """,
                entity_id,
            )
            return exists
    
    async def create(self, entity_id: str, entity_type: str,
                     created_at: Optional[datetime], updated_at: Optional[datetime],
                     entity_data: dict) -> None:
        """Create a new entity."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                f"""
                INSERT INTO {self.table_name} (entity_id, entity_type, created_at, updated_at, entity_data)
                VALUES ($1, $2, $3, $4, $5)
                """,
                entity_id,
                entity_type,
                created_at,
                updated_at,
                json.dumps(entity_data),
            )
    
    async def update(self, entity_id: str, updated_at: datetime, entity_data: dict) -> None:
        """Update an existing entity."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                f"""
                UPDATE {self.table_name}
                SET updated_at = $1, entity_data = $2
                WHERE entity_id = $3
                """,
                updated_at,
                json.dumps(entity_data),
                entity_id,
            )
