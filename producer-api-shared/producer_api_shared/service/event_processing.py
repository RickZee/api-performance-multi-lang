"""Event processing service."""

import asyncpg
import logging
from datetime import datetime
from typing import Optional, Callable, Awaitable

from ..models.event import Event
from ..repository import BusinessEventRepository, EntityRepository, EventHeaderRepository
from ..constants import ENTITY_TABLE_MAP

logger = logging.getLogger(__name__)


class EventProcessingService:
    """Service for processing events."""
    
    def __init__(
        self,
        business_event_repo: BusinessEventRepository,
        connection_factory: Callable[[], Awaitable[asyncpg.Connection]],
        api_name: str = "[producer-api]",
        should_close_connection: bool = True
    ):
        """Initialize service with repositories and connection factory.
        
        Args:
            business_event_repo: Business event repository instance
            connection_factory: Async function that returns a database connection
            api_name: API name for logging (default: "[producer-api]")
            should_close_connection: Whether to close connections after use (True for direct connections, False for pool)
        """
        self.business_event_repo = business_event_repo
        self.event_header_repo = EventHeaderRepository()
        self.connection_factory = connection_factory
        self.api_name = api_name
        self.should_close_connection = should_close_connection
        self._persisted_event_count = 0
    
    def _log_persisted_event_count(self):
        """Log persisted event count every 10 events."""
        self._persisted_event_count += 1
        if self._persisted_event_count % 10 == 0:
            logger.info(f"{self.api_name} *** Persisted events count: {self._persisted_event_count} ***")
    
    def _get_entity_repository(self, entity_type: str) -> Optional[EntityRepository]:
        """Get the appropriate entity repository for the entity type."""
        table_name = ENTITY_TABLE_MAP.get(entity_type)
        if table_name is None:
            logger.warning(f"{self.api_name} Unknown entity type: {entity_type}")
            return None
        return EntityRepository(table_name)
    
    async def process_event(self, event: Event) -> None:
        """Process a single event within a transaction.
        
        All database operations (business_events, event_headers, entities) are executed
        atomically within a single transaction. If any operation fails, all changes are rolled back.
        """
        logger.info(f"{self.api_name} Processing event: {event.event_header.event_name}")
        
        event_id = event.event_header.uuid or f"event-{datetime.utcnow().isoformat()}"
        
        # Get connection from factory
        conn = await self.connection_factory()
        
        try:
            async with conn.transaction():
                try:
                    # 1. Save entire event to business_events table
                    await self.save_business_event(event, conn=conn)
                    
                    # 2. Save event header to event_headers table
                    await self.save_event_header(event, event_id, conn=conn)
                    
                    # 3. Extract and save entities to their respective tables
                    for entity_update in event.event_body.entities:
                        await self.process_entity_update(entity_update, event_id, conn=conn)
                    
                    self._log_persisted_event_count()
                    logger.info(f"{self.api_name} Successfully processed event in transaction: {event_id}")
                except Exception as e:
                    logger.error(f"{self.api_name} Error processing event in transaction: {e}", exc_info=True)
                    # Transaction will automatically rollback on exception
                    raise
        finally:
            # Clean up connection
            if self.should_close_connection:
                # Check if connection is from a pool (has _pool attribute)
                if hasattr(conn, '_pool') and conn._pool is not None:
                    # Release connection back to pool
                    await conn._pool.release(conn)
                    logger.debug(f"{self.api_name} Connection released to pool")
                else:
                    # Close direct connection
                    await conn.close()
                    logger.debug(f"{self.api_name} Connection closed")
    
    async def save_business_event(self, event: Event, conn: Optional[asyncpg.Connection] = None) -> None:
        """Save the entire event to business_events table."""
        event_id = event.event_header.uuid or f"event-{datetime.utcnow().isoformat()}"
        event_name = event.event_header.event_name
        event_type = event.event_header.event_type
        created_date = event.event_header.created_date or datetime.utcnow()
        saved_date = event.event_header.saved_date or datetime.utcnow()
        
        # Convert event to dict for JSONB storage
        event_data = event.model_dump(mode='json')
        
        await self.business_event_repo.create(
            event_id=event_id,
            event_name=event_name,
            event_type=event_type,
            created_date=created_date,
            saved_date=saved_date,
            event_data=event_data,
            conn=conn,
        )
        logger.info(f"{self.api_name} Successfully saved business event: {event_id}")
    
    async def save_event_header(self, event: Event, event_id: str, conn: Optional[asyncpg.Connection] = None) -> None:
        """Save the event header to event_headers table."""
        event_name = event.event_header.event_name
        event_type = event.event_header.event_type
        created_date = event.event_header.created_date or datetime.utcnow()
        saved_date = event.event_header.saved_date or datetime.utcnow()
        
        # Convert eventHeader to dict for JSONB storage
        header_data = event.event_header.model_dump(mode='json')
        
        await self.event_header_repo.create(
            event_id=event_id,
            event_name=event_name,
            event_type=event_type,
            created_date=created_date,
            saved_date=saved_date,
            header_data=header_data,
            conn=conn,
        )
        logger.info(f"{self.api_name} Successfully saved event header: {event_id}")
    
    async def process_entity_update(self, entity_update, event_id: str,
                                   conn: Optional[asyncpg.Connection] = None) -> None:
        """Process a single entity update.
        
        Args:
            entity_update: EntityUpdate object with entity type, ID, and updated attributes
            event_id: Event ID that triggered this entity update
            conn: Database connection
        """
        entity_type = entity_update.entity_type
        entity_id = entity_update.entity_id
        
        if not entity_type or not entity_id:
            logger.warning(
                f"{self.api_name} Entity missing entityType or entityId, skipping"
            )
            return
        
        logger.info(
            f"{self.api_name} Processing entity creation for type: {entity_type} "
            f"and id: {entity_id}"
        )
        
        entity_repo = self._get_entity_repository(entity_type)
        if entity_repo is None:
            logger.warning(
                f"{self.api_name} Skipping entity with unknown type: {entity_type}"
            )
            return
        
        exists = await entity_repo.exists_by_entity_id(entity_id, conn=conn)
        
        if exists:
            logger.warning(
                f"{self.api_name} Entity already exists, updating: {entity_id}"
            )
            await self.update_existing_entity(entity_repo, entity_update, event_id, conn=conn)
        else:
            logger.info(
                f"{self.api_name} Entity does not exist, creating new: {entity_id}"
            )
            await self.create_new_entity(entity_repo, entity_update, event_id, conn=conn)
    
    async def create_new_entity(
        self, entity_repo: EntityRepository, entity_update,
        event_id: str, conn: Optional[asyncpg.Connection] = None
    ) -> None:
        """Create a new entity.
        
        Args:
            entity_repo: Repository for the entity type
            entity_update: EntityUpdate object with entity type, ID, and updated attributes
            event_id: Event ID that triggered this entity creation
            conn: Database connection
        """
        entity_id = entity_update.entity_id
        entity_type = entity_update.entity_type
        now = datetime.utcnow()
        
        # Extract entity data from updated_attributes
        entity_data = entity_update.updated_attributes.copy() if isinstance(
            entity_update.updated_attributes, dict
        ) else {}
        
        # Remove entityHeader from entity_data if it exists (nested structure)
        entity_header = entity_data.pop("entityHeader", None) or entity_data.pop("entity_header", None)
        
        # Extract createdAt and updatedAt from entityHeader if present, otherwise from entity_data, otherwise use now
        if entity_header and isinstance(entity_header, dict):
            created_at_str = entity_header.get("createdAt") or entity_header.get("created_at")
            updated_at_str = entity_header.get("updatedAt") or entity_header.get("updated_at")
        else:
            created_at_str = entity_data.pop("createdAt", None) or entity_data.pop("created_at", None)
            updated_at_str = entity_data.pop("updatedAt", None) or entity_data.pop("updated_at", None)
        
        # Parse datetime strings to datetime objects
        created_at = self._parse_datetime(created_at_str) if created_at_str else now
        updated_at = self._parse_datetime(updated_at_str) if updated_at_str else now
        
        await entity_repo.create(
            entity_id=entity_id,
            entity_type=entity_type,
            created_at=created_at,
            updated_at=updated_at,
            entity_data=entity_data,
            event_id=event_id,
            conn=conn,
        )
        logger.info(f"{self.api_name} Successfully created entity: {entity_id}")
    
    def _parse_datetime(self, dt_str: str) -> datetime:
        """Parse datetime string to datetime object."""
        if isinstance(dt_str, datetime):
            return dt_str
        
        try:
            # Try ISO format
            return datetime.fromisoformat(dt_str.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            try:
                # Try parsing with dateutil
                from dateutil import parser
                return parser.parse(dt_str)
            except Exception:
                return datetime.utcnow()
    
    async def update_existing_entity(
        self, entity_repo: EntityRepository, entity_update,
        event_id: str, conn: Optional[asyncpg.Connection] = None
    ) -> None:
        """Update an existing entity.
        
        Args:
            entity_repo: Repository for the entity type
            entity_update: EntityUpdate object with entity type, ID, and updated attributes
            event_id: Event ID that triggered this entity update
            conn: Database connection
        """
        entity_id = entity_update.entity_id
        updated_at = datetime.utcnow()
        
        # Extract entity data from updated_attributes
        entity_data = entity_update.updated_attributes.copy() if isinstance(
            entity_update.updated_attributes, dict
        ) else {}
        
        # Remove entityHeader from entity_data if it exists
        entity_data.pop("entityHeader", None)
        entity_data.pop("entity_header", None)
        
        # Remove entityHeader fields that might be at top level
        entity_data.pop("createdAt", None)
        entity_data.pop("created_at", None)
        entity_data.pop("updatedAt", None)
        entity_data.pop("updated_at", None)
        
        await entity_repo.update(
            entity_id=entity_id,
            updated_at=updated_at,
            entity_data=entity_data,
            event_id=event_id,
            conn=conn,
        )
        logger.info(f"{self.api_name} Successfully updated entity: {entity_id}")
