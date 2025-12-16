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
        import asyncio
        
        # Log event loop ID for debugging
        try:
            process_loop = asyncio.get_running_loop()
            process_loop_id = id(process_loop)
            logger.debug(f"{self.api_name} process_event running in event loop: {process_loop_id}")
        except RuntimeError:
            process_loop_id = "unknown"
            logger.warning(f"{self.api_name} No running loop detected in process_event")
        
        event_id = event.event_header.uuid or f"event-{datetime.utcnow().isoformat()}"
        logger.info(f"{self.api_name} Starting event processing: {event_id} (loop_id={process_loop_id})")
        
        # Get connection from factory
        logger.debug(f"{self.api_name} Calling connection factory (loop_id={process_loop_id})")
        conn = await self.connection_factory()
        logger.info(f"{self.api_name} Connection obtained successfully (loop_id={process_loop_id})")
        
        try:
            logger.debug(f"{self.api_name} Starting transaction (loop_id={process_loop_id})")
            async with conn.transaction():
                logger.debug(f"{self.api_name} Transaction started, saving business event")
                try:
                    # 1. Save entire event to business_events table
                    await self.save_business_event(event, conn=conn)
                    logger.debug(f"{self.api_name} Business event saved")
                    
                    # 2. Save event header to event_headers table
                    await self.save_event_header(event, event_id, conn=conn)
                    logger.debug(f"{self.api_name} Event header saved")
                    
                    # 3. Extract and save entities to their respective tables
                    for idx, entity in enumerate(event.entities):
                        logger.debug(f"{self.api_name} Processing entity {idx+1}/{len(event.entities)}")
                        await self.process_entity_update(entity, event_id, conn=conn)
                    
                    self._log_persisted_event_count()
                    logger.info(f"{self.api_name} Successfully processed event in transaction: {event_id}")
                except Exception as e:
                    logger.error(f"{self.api_name} Error processing event in transaction: {e}", exc_info=True)
                    # Transaction will automatically rollback on exception
                    raise
        finally:
            # Clean up connection
            logger.debug(f"{self.api_name} Cleaning up connection (loop_id={process_loop_id})")
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
    
    async def process_entity_update(self, entity, event_id: str,
                                   conn: Optional[asyncpg.Connection] = None) -> None:
        """Process a single entity update.
        
        Args:
            entity: Entity object with entity header and flat properties
            event_id: Event ID that triggered this entity update
            conn: Database connection
        """
        entity_type = entity.entity_header.entity_type
        entity_id = entity.entity_header.entity_id
        
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
            await self.update_existing_entity(entity_repo, entity, event_id, conn=conn)
        else:
            logger.info(
                f"{self.api_name} Entity does not exist, creating new: {entity_id}"
            )
            await self.create_new_entity(entity_repo, entity, event_id, conn=conn)
    
    async def create_new_entity(
        self, entity_repo: EntityRepository, entity,
        event_id: str, conn: Optional[asyncpg.Connection] = None
    ) -> None:
        """Create a new entity.
        
        Args:
            entity_repo: Repository for the entity type
            entity: Entity object with entity header and flat properties
            event_id: Event ID that triggered this entity creation
            conn: Database connection
        """
        entity_id = entity.entity_header.entity_id
        entity_type = entity.entity_header.entity_type
        now = datetime.utcnow()
        
        # Extract entity data from entity properties (excluding entityHeader)
        entity_dict = entity.model_dump(mode='json')
        entity_data = {k: v for k, v in entity_dict.items() if k != 'entityHeader'}
        
        # Use createdAt and updatedAt from entityHeader
        created_at = entity.entity_header.created_at if entity.entity_header.created_at else now
        updated_at = entity.entity_header.updated_at if entity.entity_header.updated_at else now
        
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
        self, entity_repo: EntityRepository, entity,
        event_id: str, conn: Optional[asyncpg.Connection] = None
    ) -> None:
        """Update an existing entity.
        
        Args:
            entity_repo: Repository for the entity type
            entity: Entity object with entity header and flat properties
            event_id: Event ID that triggered this entity update
            conn: Database connection
        """
        entity_id = entity.entity_header.entity_id
        updated_at = datetime.utcnow()
        
        # Extract entity data from entity properties (excluding entityHeader)
        entity_dict = entity.model_dump(mode='json')
        entity_data = {k: v for k, v in entity_dict.items() if k != 'entityHeader'}
        
        await entity_repo.update(
            entity_id=entity_id,
            updated_at=updated_at,
            entity_data=entity_data,
            event_id=event_id,
            conn=conn,
        )
        logger.info(f"{self.api_name} Successfully updated entity: {entity_id}")
