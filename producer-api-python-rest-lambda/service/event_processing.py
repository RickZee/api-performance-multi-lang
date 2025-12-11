"""Event processing service."""

import json
import logging
from datetime import datetime
from typing import Optional

from constants import API_NAME
from models.event import Event, EntityUpdate
from repository import BusinessEventRepository, EntityRepository, get_connection_pool

logger = logging.getLogger(__name__)

# Entity type to table name mapping
ENTITY_TABLE_MAP = {
    "Car": "car_entities",
    "Loan": "loan_entities",
    "LoanPayment": "loan_payment_entities",
    "ServiceRecord": "service_record_entities",
}


class EventProcessingService:
    """Service for processing events."""
    
    def __init__(self, business_event_repo: BusinessEventRepository, pool):
        """Initialize service with repositories."""
        self.business_event_repo = business_event_repo
        self.pool = pool
        self._persisted_event_count = 0
    
    def _log_persisted_event_count(self):
        """Log persisted event count every 10 events."""
        self._persisted_event_count += 1
        if self._persisted_event_count % 10 == 0:
            logger.info(f"{API_NAME} *** Persisted events count: {self._persisted_event_count} ***")
    
    def _get_entity_repository(self, entity_type: str) -> Optional[EntityRepository]:
        """Get the appropriate entity repository for the entity type."""
        table_name = ENTITY_TABLE_MAP.get(entity_type)
        if table_name is None:
            logger.warning(f"{API_NAME} Unknown entity type: {entity_type}")
            return None
        return EntityRepository(self.pool, table_name)
    
    async def process_event(self, event: Event) -> None:
        """Process a single event."""
        logger.info(f"{API_NAME} Processing event: {event.event_header.event_name}")
        
        # 1. Save entire event to business_events table
        await self.save_business_event(event)
        
        # 2. Extract and save entities to their respective tables
        for entity_update in event.event_body.entities:
            await self.process_entity_update(entity_update)
        
        self._log_persisted_event_count()
    
    async def save_business_event(self, event: Event) -> None:
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
        )
        logger.info(f"{API_NAME} Successfully saved business event: {event_id}")
    
    async def process_entity_update(self, entity_update: EntityUpdate) -> None:
        """Process a single entity update."""
        logger.info(
            f"{API_NAME} Processing entity creation for type: {entity_update.entity_type} "
            f"and id: {entity_update.entity_id}"
        )
        
        entity_repo = self._get_entity_repository(entity_update.entity_type)
        if entity_repo is None:
            logger.warning(
                f"{API_NAME} Skipping entity with unknown type: {entity_update.entity_type}"
            )
            return
        
        exists = await entity_repo.exists_by_entity_id(entity_update.entity_id)
        
        if exists:
            logger.warning(
                f"{API_NAME} Entity already exists, updating: {entity_update.entity_id}"
            )
            await self.update_existing_entity(entity_repo, entity_update)
        else:
            logger.info(
                f"{API_NAME} Entity does not exist, creating new: {entity_update.entity_id}"
            )
            await self.create_new_entity(entity_repo, entity_update)
    
    async def create_new_entity(
        self, entity_repo: EntityRepository, entity_update: EntityUpdate
    ) -> None:
        """Create a new entity."""
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
        )
        logger.info(f"{API_NAME} Successfully created entity: {entity_id}")
    
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
        self, entity_repo: EntityRepository, entity_update: EntityUpdate
    ) -> None:
        """Update an existing entity."""
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
        )
        logger.info(f"{API_NAME} Successfully updated entity: {entity_id}")
