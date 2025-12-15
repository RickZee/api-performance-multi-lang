"""Event models for Producer API."""

from datetime import datetime
from typing import Any, List, Optional

from dateutil import parser
from pydantic import BaseModel, Field, field_validator


class EventHeader(BaseModel):
    """Event header containing metadata."""
    
    uuid: Optional[str] = None
    event_name: str = Field(..., alias="eventName")
    created_date: Optional[datetime] = Field(None, alias="createdDate")
    saved_date: Optional[datetime] = Field(None, alias="savedDate")
    event_type: Optional[str] = Field(None, alias="eventType")
    
    @field_validator("created_date", "saved_date", mode="before")
    @classmethod
    def parse_flexible_date(cls, v: Any) -> Optional[datetime]:
        """Parse date from ISO 8601 string or Unix timestamp (milliseconds)."""
        if v is None:
            return None
        
        if isinstance(v, datetime):
            return v
        
        if isinstance(v, str):
            # Try ISO 8601 formats first
            try:
                return parser.isoparse(v)
            except (ValueError, TypeError):
                pass
            
            # Try parsing as numeric string (timestamp in milliseconds)
            try:
                ms = int(v)
                return datetime.fromtimestamp(ms / 1000.0)
            except (ValueError, TypeError):
                pass
            
            raise ValueError(f"Unable to parse date string: {v}")
        
        if isinstance(v, (int, float)):
            # JSON numbers are parsed as int/float
            ms = int(v)
            return datetime.fromtimestamp(ms / 1000.0)
        
        raise ValueError(f"Unsupported date type: {type(v)}")
    
    class Config:
        """Pydantic config."""
        populate_by_name = True
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None
        }


class EntityUpdate(BaseModel):
    """Entity update information."""
    
    entity_type: str = Field(..., alias="entityType")
    entity_id: str = Field(..., alias="entityId")
    updated_attributes: Any = Field(..., alias="updatedAttributes")
    
    class Config:
        """Pydantic config."""
        populate_by_name = True


class EventBody(BaseModel):
    """Event body containing entity updates."""
    
    entities: List[EntityUpdate]


class Event(BaseModel):
    """Complete event structure."""
    
    event_header: EventHeader = Field(..., alias="eventHeader")
    event_body: EventBody = Field(..., alias="eventBody")
    
    class Config:
        """Pydantic config."""
        populate_by_name = True
