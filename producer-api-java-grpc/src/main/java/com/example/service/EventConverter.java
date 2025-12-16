package com.example.service;

import com.example.dto.Event;
import com.example.dto.EventHeader;
import com.example.dto.Entity;
import com.example.dto.EntityHeader;
import com.example.grpc.EventRequest;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Component
@RequiredArgsConstructor
public class EventConverter {
    
    private final ObjectMapper objectMapper;

    public Event convertFromProto(EventRequest request) {
        Event event = new Event();
        
        // Convert EventHeader
        if (request.hasEventHeader()) {
            var protoHeader = request.getEventHeader();
            EventHeader header = new EventHeader();
            header.setUuid(protoHeader.getUuid().isEmpty() ? null : protoHeader.getUuid());
            header.setEventName(protoHeader.getEventName());
            header.setEventType(protoHeader.getEventType().isEmpty() ? null : protoHeader.getEventType());
            
            // Parse dates
            if (!protoHeader.getCreatedDate().isEmpty()) {
                header.setCreatedDate(parseDateTime(protoHeader.getCreatedDate()));
            }
            if (!protoHeader.getSavedDate().isEmpty()) {
                header.setSavedDate(parseDateTime(protoHeader.getSavedDate()));
            }
            
            event.setEventHeader(header);
        }
        
        // Convert entities
        List<Entity> entities = new ArrayList<>();
        
        for (var protoEntity : request.getEntitiesList()) {
            // Convert entityHeader
            EntityHeader entityHeader = new EntityHeader();
            entityHeader.setEntityId(protoEntity.getEntityHeader().getEntityId());
            entityHeader.setEntityType(protoEntity.getEntityHeader().getEntityType());
            entityHeader.setCreatedAt(parseDateTime(protoEntity.getEntityHeader().getCreatedAt()));
            entityHeader.setUpdatedAt(parseDateTime(protoEntity.getEntityHeader().getUpdatedAt()));
            
            // Convert properties_json to map
            Map<String, Object> properties = new HashMap<>();
            if (!protoEntity.getPropertiesJson().isEmpty()) {
                try {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> props = objectMapper.readValue(protoEntity.getPropertiesJson(), Map.class);
                    properties.putAll(props);
                } catch (Exception e) {
                    // If parsing fails, properties will be empty
                }
            }
            
            Entity entity = new Entity();
            entity.setEntityHeader(entityHeader);
            entity.setProperties(properties);
            
            entities.add(entity);
        }
        
        event.setEntities(entities);
        
        return event;
    }

    private OffsetDateTime parseDateTime(String dateStr) {
        if (dateStr == null || dateStr.isEmpty()) {
            return null;
        }
        
        try {
            // Try ISO 8601 format
            return OffsetDateTime.parse(dateStr);
        } catch (Exception e) {
            try {
                // Try parsing as Unix timestamp (milliseconds)
                long ms = Long.parseLong(dateStr);
                return OffsetDateTime.ofInstant(
                        java.time.Instant.ofEpochMilli(ms),
                        java.time.ZoneOffset.UTC
                );
            } catch (Exception e2) {
                return null;
            }
        }
    }
}

