"""Business event repository for database operations."""

import asyncpg
import json
import logging
from typing import Optional
from datetime import datetime

logger = logging.getLogger(__name__)


class BusinessEventRepository:
    """Repository for business event database operations."""
    
    def __init__(self, pool: asyncpg.Pool):
        """Initialize repository with connection pool."""
        self.pool = pool
    
    async def create(self, event_id: str, event_name: str, event_type: Optional[str],
                     created_date: Optional[datetime], saved_date: Optional[datetime],
                     event_data: dict) -> None:
        """Create a new business event."""
        async with self.pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO business_events (id, event_name, event_type, created_date, saved_date, event_data)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                event_id,
                event_name,
                event_type,
                created_date,
                saved_date,
                json.dumps(event_data),
            )
