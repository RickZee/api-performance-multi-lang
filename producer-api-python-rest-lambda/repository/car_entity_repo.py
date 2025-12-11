"""Car entity repository for database operations."""

import asyncpg
import logging
from typing import Optional

from models.entity import CarEntity

logger = logging.getLogger(__name__)


class CarEntityRepository:
    """Repository for car entity database operations."""
    
    def __init__(self, pool: asyncpg.Pool):
        """Initialize repository with connection pool."""
        self.pool = pool
    
    async def find_by_entity_type_and_id(
        self, entity_type: str, entity_id: str
    ) -> Optional[CarEntity]:
        """Find entity by entity type and ID."""
        async with self.pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                SELECT id, entity_type, created_at, updated_at, data
                FROM car_entities
                WHERE entity_type = $1 AND id = $2
                """,
                entity_type,
                entity_id,
            )
            
            if row is None:
                return None
            
            return CarEntity(
                id=row["id"],
                entity_type=row["entity_type"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                data=row["data"],
            )
    
    async def exists_by_entity_type_and_id(
        self, entity_type: str, entity_id: str
    ) -> bool:
        """Check if entity exists by entity type and ID."""
        async with self.pool.acquire() as conn:
            exists = await conn.fetchval(
                """
                SELECT EXISTS(SELECT 1 FROM car_entities WHERE entity_type = $1 AND id = $2)
                """,
                entity_type,
                entity_id,
            )
            return exists
    
    async def create(self, entity: CarEntity) -> None:
        """Create a new entity."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO car_entities (id, entity_type, created_at, updated_at, data)
                VALUES ($1, $2, $3, $4, $5)
                """,
                entity.id,
                entity.entity_type,
                entity.created_at,
                entity.updated_at,
                entity.data,
            )
    
    async def update(self, entity: CarEntity) -> None:
        """Update an existing entity."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE car_entities
                SET entity_type = $1, updated_at = $2, data = $3
                WHERE id = $4
                """,
                entity.entity_type,
                entity.updated_at,
                entity.data,
                entity.id,
            )
