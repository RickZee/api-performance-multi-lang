"""Base repository interfaces and protocols."""

from typing import Protocol
import asyncpg


class ConnectionProvider(Protocol):
    """Protocol for connection providers.
    
    Repositories should always accept connections explicitly via the `conn` parameter.
    This allows for transaction management at the service layer.
    """
    pass
