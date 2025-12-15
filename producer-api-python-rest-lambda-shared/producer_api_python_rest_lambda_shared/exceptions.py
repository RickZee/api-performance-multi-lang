"""Shared exceptions for Producer API."""


class DuplicateEventError(Exception):
    """Exception raised when attempting to create an event with an existing ID."""
    def __init__(self, event_id: str, message: str = None):
        self.event_id = event_id
        self.message = message or f"Event with ID '{event_id}' already exists"
        super().__init__(self.message)
