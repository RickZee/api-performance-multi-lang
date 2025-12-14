package com.example.metadata.testutil;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class TestEventGenerator {
    
    public static Map<String, Object> validCarCreatedEvent() {
        Map<String, Object> event = new HashMap<>();
        
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        
        Map<String, Object> entityHeader = new HashMap<>();
        entityHeader.put("entityId", "CAR-001");
        entityHeader.put("entityType", "Car");
        entityHeader.put("createdAt", Instant.now().toString());
        entityHeader.put("updatedAt", Instant.now().toString());
        
        Map<String, Object> car = new HashMap<>();
        car.put("entityHeader", entityHeader);
        car.put("id", "CAR-001");
        car.put("vin", "5TDJKRFH4LS123456");
        car.put("make", "Tesla");
        car.put("model", "Model S");
        car.put("year", 2024);
        car.put("color", "Red");
        car.put("mileage", 0);
        
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of(car));
        
        return event;
    }
    
    public static Map<String, Object> invalidEventMissingRequired() {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        // Missing required fields
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        return event;
    }
    
    public static Map<String, Object> invalidEventWrongType() {
        Map<String, Object> event = new HashMap<>();
        
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        
        Map<String, Object> entityHeader = new HashMap<>();
        entityHeader.put("entityId", "CAR-001");
        entityHeader.put("entityType", "Car");
        entityHeader.put("createdAt", Instant.now().toString());
        entityHeader.put("updatedAt", Instant.now().toString());
        
        Map<String, Object> car = new HashMap<>();
        car.put("entityHeader", entityHeader);
        car.put("id", "CAR-001");
        car.put("vin", "5TDJKRFH4LS123456");
        car.put("make", "Tesla");
        car.put("model", "Model S");
        car.put("year", "2024"); // Wrong type - should be integer
        car.put("color", "Red");
        car.put("mileage", 0);
        
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of(car));
        
        return event;
    }
    
    public static Map<String, Object> invalidEventInvalidPattern() {
        Map<String, Object> event = new HashMap<>();
        
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        
        Map<String, Object> entityHeader = new HashMap<>();
        entityHeader.put("entityId", "CAR-001");
        entityHeader.put("entityType", "Car");
        entityHeader.put("createdAt", Instant.now().toString());
        entityHeader.put("updatedAt", Instant.now().toString());
        
        Map<String, Object> car = new HashMap<>();
        car.put("entityHeader", entityHeader);
        car.put("id", "CAR-001");
        car.put("vin", "INVALID-VIN"); // Invalid VIN pattern
        car.put("make", "Tesla");
        car.put("model", "Model S");
        car.put("year", 2024);
        car.put("color", "Red");
        car.put("mileage", 0);
        
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of(car));
        
        return event;
    }
    
    public static Map<String, Object> eventWithNulls() {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", null); // Null value
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        return event;
    }
    
    public static Map<String, Object> eventWithTypeCoercion() {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        
        Map<String, Object> entityHeader = new HashMap<>();
        entityHeader.put("entityId", "CAR-001");
        entityHeader.put("entityType", "Car");
        entityHeader.put("createdAt", Instant.now().toString());
        entityHeader.put("updatedAt", Instant.now().toString());
        
        Map<String, Object> car = new HashMap<>();
        car.put("entityHeader", entityHeader);
        car.put("id", "CAR-001");
        car.put("vin", "5TDJKRFH4LS123456");
        car.put("make", "Tesla");
        car.put("model", "Model S");
        car.put("year", "2024"); // String where integer expected
        car.put("color", "Red");
        car.put("mileage", "0"); // String where integer expected
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of(car));
        return event;
    }
    
    public static Map<String, Object> eventWithInvalidEnum() {
        Map<String, Object> event = new HashMap<>();
        Map<String, Object> eventHeader = new HashMap<>();
        eventHeader.put("uuid", "550e8400-e29b-41d4-a716-446655440000");
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "InvalidType"); // Invalid enum
        eventHeader.put("createdDate", Instant.now().toString());
        eventHeader.put("savedDate", Instant.now().toString());
        event.put("eventHeader", eventHeader);
        event.put("entities", List.of());
        return event;
    }
    
    public static Map<String, Object> eventWithOutOfRange() {
        Map<String, Object> event = validCarCreatedEvent();
        @SuppressWarnings("unchecked")
        Map<String, Object> car = (Map<String, Object>) ((List<?>) event.get("entities")).get(0);
        car.put("year", 3000); // Out of range (max 2030)
        return event;
    }
    
    public static Map<String, Object> eventWithAdditionalProperties() {
        Map<String, Object> event = validCarCreatedEvent();
        event.put("extraField", "not allowed");
        return event;
    }
}
