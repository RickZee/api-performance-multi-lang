"""Car entity model."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class CarEntity(BaseModel):
    """Car entity model."""
    
    id: str
    entity_type: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    data: str  # JSON string
    
    class Config:
        """Pydantic config."""
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None
        }
