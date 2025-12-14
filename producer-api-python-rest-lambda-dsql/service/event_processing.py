"""Event processing service."""

import asyncpg
import asyncio
import logging
from datetime import datetime
from typing import Optional
import uuid

from constants import API_NAME
from models.event import Event, EntityUpdate
from repository import BusinessEventRepository, EntityRepository, EventHeaderRepository, get_connection
from config import LambdaConfig
from service.retry_utils import retry_on_oc000, classify_dsql_error, is_oc000_error

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
    
    def __init__(self, business_event_repo: BusinessEventRepository, config: LambdaConfig):
        """Initialize service with repositories and config."""
        self.business_event_repo = business_event_repo
        self.event_header_repo = EventHeaderRepository(None)  # No pool needed, connections passed directly
        self.config = config
        self._persisted_event_count = 0
    
    def _log_persisted_event_count(self):
        """Log persisted event count every 10 events."""
        self._persisted_event_count += 1
        if self._persisted_event_count % 10 == 0:
            logger.info(f"{API_NAME} *** Persisted events count: {self._persisted_event_count} ***")
    
    def _get_entity_repository(self, entity_type: str) -> Optional[EntityRepository]:
        """Get the appropriate entity repository for the entity type."""
        # Use entity_type directly from the model (no need for title case conversion)
        # Keep special case handling for compound types if needed
        table_name = ENTITY_TABLE_MAP.get(entity_type)
        if table_name is None:
            logger.warning(f"{API_NAME} Unknown entity type: {entity_type}")
            return None
        return EntityRepository(None, table_name)  # No pool needed, connections passed directly
    
    @retry_on_oc000(stop_after=5, min_wait=0.1, max_wait=2.0)
    async def _execute_transaction(self, event: Event, event_id: str, transaction_id: str) -> None:
        """Execute transaction with retry logic (wrapped by tenacity decorator).
        
        This method is decorated with @retry_on_oc000 to automatically retry
        on OC000 transaction conflicts with exponential backoff and jitter.
        
        Args:
            event: Event to process
            event_id: Event ID
            transaction_id: Unique transaction ID for logging
        """
        # Create direct connection (no pooling) - new connection for each retry attempt
        conn = await get_connection(self.config)
        
        try:
            async with conn.transaction():
                # 1. Save entire event to business_events table
                await self.save_business_event(event, conn=conn)
                
                # 2. Save event header to event_headers table
                await self.save_event_header(event, event_id, conn=conn)
                
                # 3. Extract and save entities to their respective tables
                for entity_update in event.event_body.entities:
                    await self.process_entity_update(entity_update, event_id, conn=conn)
                
                self._log_persisted_event_count()
                logger.info(
                    f"{API_NAME} Successfully processed event in transaction: {event_id}",
                    extra={
                        'event_id': event_id,
                        'event_type': event.event_header.event_type,
                        'event_name': event.event_header.event_name,
                        'transaction_id': transaction_id,
                    }
                )
        finally:
            # Always close connection
            await conn.close()
    
    async def process_event(self, event: Event) -> None:
        """Process a single event within a transaction with retry logic for OC000 conflicts.
        
        All database operations (business_events, event_headers, entities) are executed
        atomically within a single transaction. If any operation fails, all changes are rolled back.
        
        Uses direct connections (no pooling) to avoid DSQL compatibility issues.
        
        Implements transaction-level retry for DSQL OC000 errors using tenacity library
        with exponential backoff and jitter to avoid thundering herd problems.
        
        Error Classification:
        - OC000 errors: Retried automatically (up to 5 attempts)
        - DuplicateEventError: Not retried (returns 409 Conflict)
        - Connection errors: Retried automatically
        - Other errors: Not retried (fail immediately)
        """
        event_id = event.event_header.uuid or f"event-{datetime.utcnow().isoformat()}"
        event_type = event.event_header.event_type or 'Unknown'
        event_name = event.event_header.event_name or 'Unknown'
        transaction_id = str(uuid.uuid4())  # Unique transaction ID for logging
        
        logger.info(
            f"{API_NAME} Processing event: {event_name}",
            extra={
                'event_id': event_id,
                'event_type': event_type,
                'event_name': event_name,
                'transaction_id': transaction_id,
            }
        )
        
        # Enhanced logging for Payment and Service events to diagnose failures
        if event_type in ('LoanPaymentSubmitted', 'CarServiceDone'):
            entity_info = []
            for entity in event.event_body.entities:
                entity_info.append({
                    'entity_type': entity.entity_type,
                    'entity_id': entity.entity_id,
                    'has_loan_id': 'loanId' in (entity.updated_attributes or {}),
                    'has_car_id': 'carId' in (entity.updated_attributes or {}),
                })
            logger.info(
                f"{API_NAME} Payment/Service event details: {event_name}",
                extra={
                    'event_id': event_id,
                    'event_type': event_type,
                    'event_name': event_name,
                    'transaction_id': transaction_id,
                    'entity_count': len(event.event_body.entities),
                    'entity_info': entity_info,
                }
            )
        
        try:
            # Execute transaction with automatic retry on OC000 errors
            await self._execute_transaction(event, event_id, transaction_id)
            
        except Exception as e:
            # Classify error for structured logging
            is_retryable, error_type, sqlstate = classify_dsql_error(e)
            
            # Log error with full context
            log_context = {
                'event_id': event_id,
                'event_type': event_type,
                'event_name': event_name,
                'transaction_id': transaction_id,
                'error_type': error_type,
                'sqlstate': sqlstate,
                'is_retryable': is_retryable,
                'exception': str(e),
            }
            
            if error_type == 'OC000_TRANSACTION_CONFLICT':
                # This should not happen if retry logic works correctly
                # But log it if all retries exhausted
                # Enhanced logging for Payment/Service events
                if event_type in ('LoanPaymentSubmitted', 'CarServiceDone'):
                    logger.error(
                        f"{API_NAME} OC000 transaction conflict - all retries exhausted for {event_name}",
                        extra={
                            **log_context,
                            'entity_types': [e.entity_type for e in event.event_body.entities],
                            'entity_ids': [e.entity_id for e in event.event_body.entities],
                            'retry_exhausted': True,
                        },
                        exc_info=True
                    )
                else:
                    logger.error(
                        f"{API_NAME} OC000 transaction conflict - all retries exhausted",
                        extra=log_context,
                        exc_info=True
                    )
            elif error_type == 'DUPLICATE_EVENT':
                logger.warning(
                    f"{API_NAME} Duplicate event detected",
                    extra=log_context
                )
            else:
                logger.error(
                    f"{API_NAME} Error processing event: {error_type}",
                    extra=log_context,
                    exc_info=True
                )
            
            # Re-raise exception (will be handled by lambda_handler)
            raise
    
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
        logger.info(f"{API_NAME} Successfully saved business event: {event_id}")
    
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
        logger.info(f"{API_NAME} Successfully saved event header: {event_id}")
    
    async def process_entity_update(self, entity_update: EntityUpdate, event_id: str,
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
                f"{API_NAME} Entity missing entityType or entityId, skipping"
            )
            return
        
        logger.info(
            f"{API_NAME} Processing entity creation for type: {entity_type} "
            f"and id: {entity_id}"
        )
        
        entity_repo = self._get_entity_repository(entity_type)
        if entity_repo is None:
            logger.warning(
                f"{API_NAME} Skipping entity with unknown type: {entity_type}"
            )
            return
        
        exists = await entity_repo.exists_by_entity_id(entity_id, conn=conn)
        
        if exists:
            logger.warning(
                f"{API_NAME} Entity already exists, updating: {entity_id}"
            )
            await self.update_existing_entity(entity_repo, entity_update, event_id, conn=conn)
        else:
            logger.info(
                f"{API_NAME} Entity does not exist, creating new: {entity_id}"
            )
            await self.create_new_entity(entity_repo, entity_update, event_id, conn=conn)
    
    async def create_new_entity(
        self, entity_repo: EntityRepository, entity_update: EntityUpdate,
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
        self, entity_repo: EntityRepository, entity_update: EntityUpdate,
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
        logger.info(f"{API_NAME} Successfully updated entity: {entity_id}")
