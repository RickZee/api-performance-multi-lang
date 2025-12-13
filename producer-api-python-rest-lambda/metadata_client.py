"""Metadata service client for schema validation."""

import json
import logging
import os
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin

import httpx

logger = logging.getLogger(__name__)


class MetadataClient:
    """Client for interacting with the metadata service for schema validation."""

    def __init__(self, base_url: Optional[str] = None, timeout: float = 5.0):
        """
        Initialize the metadata client.

        Args:
            base_url: Base URL of the metadata service. If None, validation is disabled.
            timeout: Request timeout in seconds.
        """
        self.base_url = base_url or os.getenv("METADATA_SERVICE_URL", "")
        self.timeout = timeout
        self.enabled = bool(self.base_url)

    def is_enabled(self) -> bool:
        """Check if metadata service is enabled."""
        return self.enabled

    async def validate_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate an event against the schema.

        Args:
            event: Event dictionary to validate.

        Returns:
            Validation result with 'valid' boolean and optional 'errors' list.
        """
        if not self.enabled:
            return {"valid": True, "version": ""}

        url = urljoin(self.base_url, "/api/v1/validate")
        payload = {"event": event}

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(url, json=payload)
                
                if response.status_code == 200:
                    return response.json()
                elif response.status_code == 422:
                    # Validation failed
                    return response.json()
                else:
                    logger.warning(
                        f"Metadata service returned unexpected status: {response.status_code}"
                    )
                    # Fail open: allow event through if service has issues
                    return {"valid": True, "version": ""}
        except httpx.TimeoutException:
            logger.warning("Metadata service timeout, skipping validation")
            # Fail open on timeout
            return {"valid": True, "version": ""}
        except httpx.RequestError as e:
            logger.warning(f"Metadata service unavailable, skipping validation: {e}")
            # Fail open if service is unavailable
            return {"valid": True, "version": ""}
        except Exception as e:
            logger.error(f"Unexpected error during validation: {e}", exc_info=True)
            # Fail open on unexpected errors
            return {"valid": True, "version": ""}

