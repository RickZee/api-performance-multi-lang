package com.example.e2e.fixtures;

import com.example.e2e.model.EventHeader;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Generator for test events matching the exact structure from raw-event-headers topic.
 */
public class TestEventGenerator {
    
    private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());
    
    /**
     * Generate a CarCreated event.
     */
    public static EventHeader generateCarCreatedEvent(String eventId) {
        String timestamp = Instant.now().toString();
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarCreated\",\"eventType\":\"CarCreated\",\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        return EventHeader.builder()
            .id(eventId != null ? eventId : UUID.randomUUID().toString())
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
    }
    
    /**
     * Generate a LoanCreated event.
     */
    public static EventHeader generateLoanCreatedEvent(String eventId) {
        String timestamp = Instant.now().toString();
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"LoanCreated\",\"eventType\":\"LoanCreated\",\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        return EventHeader.builder()
            .id(eventId != null ? eventId : UUID.randomUUID().toString())
            .eventName("LoanCreated")
            .eventType("LoanCreated")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
    }
    
    /**
     * Generate a LoanPaymentSubmitted event.
     */
    public static EventHeader generateLoanPaymentEvent(String eventId) {
        String timestamp = Instant.now().toString();
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"LoanPaymentSubmitted\",\"eventType\":\"LoanPaymentSubmitted\",\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        return EventHeader.builder()
            .id(eventId != null ? eventId : UUID.randomUUID().toString())
            .eventName("LoanPaymentSubmitted")
            .eventType("LoanPaymentSubmitted")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
    }
    
    /**
     * Generate a CarServiceDone event.
     */
    public static EventHeader generateServiceEvent(String eventId) {
        String timestamp = Instant.now().toString();
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"CarServiceDone\",\"eventType\":\"CarServiceDone\",\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, timestamp, timestamp
        );
        
        return EventHeader.builder()
            .id(eventId != null ? eventId : UUID.randomUUID().toString())
            .eventName("CarServiceDone")
            .eventType("CarServiceDone")
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("c")
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
    }
    
    /**
     * Generate an event with update operation (should be filtered out for most event types).
     */
    public static EventHeader generateUpdateEvent(String eventType, String eventId) {
        String timestamp = Instant.now().toString();
        String headerData = String.format(
            "{\"uuid\":\"%s\",\"eventName\":\"%s\",\"eventType\":\"%s\",\"createdDate\":\"%s\",\"savedDate\":\"%s\"}",
            eventId, eventType, eventType, timestamp, timestamp
        );
        
        return EventHeader.builder()
            .id(eventId != null ? eventId : UUID.randomUUID().toString())
            .eventName(eventType)
            .eventType(eventType)
            .createdDate(timestamp)
            .savedDate(timestamp)
            .headerData(headerData)
            .op("u") // Update operation
            .table("event_headers")
            .tsMs(Instant.now().toEpochMilli())
            .build();
    }
    
    /**
     * Generate a batch of mixed event types.
     */
    public static List<EventHeader> generateMixedEventBatch(int count) {
        List<EventHeader> events = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            String eventId = "test-event-" + i;
            switch (i % 4) {
                case 0:
                    events.add(generateCarCreatedEvent(eventId));
                    break;
                case 1:
                    events.add(generateLoanCreatedEvent(eventId));
                    break;
                case 2:
                    events.add(generateLoanPaymentEvent(eventId));
                    break;
                case 3:
                    events.add(generateServiceEvent(eventId));
                    break;
            }
        }
        return events;
    }
    
    /**
     * Generate a batch of loan created events with sequential IDs.
     */
    public static List<EventHeader> generateLoanCreatedEventBatch(String eventType, int count) {
        return generateEventBatch(eventType, count);
    }
    
    /**
     * Generate a batch of events of a specific type.
     */
    public static List<EventHeader> generateEventBatch(String eventType, int count) {
        List<EventHeader> events = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            String eventId = "test-" + eventType.toLowerCase() + "-" + i;
            switch (eventType) {
                case "CarCreated":
                    events.add(generateCarCreatedEvent(eventId));
                    break;
                case "LoanCreated":
                    events.add(generateLoanCreatedEvent(eventId));
                    break;
                case "LoanPaymentSubmitted":
                    events.add(generateLoanPaymentEvent(eventId));
                    break;
                case "CarServiceDone":
                    events.add(generateServiceEvent(eventId));
                    break;
                default:
                    throw new IllegalArgumentException("Unknown event type: " + eventType);
            }
        }
        return events;
    }
}

