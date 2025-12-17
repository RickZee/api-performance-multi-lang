package com.example.repository;

public class DuplicateEventError extends RuntimeException {
    private final String eventId;
    private final String message;

    public DuplicateEventError(String eventId, String message) {
        super(message != null ? message : "Event with ID '" + eventId + "' already exists");
        this.eventId = eventId;
        this.message = message != null ? message : "Event with ID '" + eventId + "' already exists";
    }

    public String getEventId() {
        return eventId;
    }

    @Override
    public String getMessage() {
        return message;
    }
}
