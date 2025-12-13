package com.example.service;

import com.example.dto.Event;
import com.example.dto.EventBody;
import com.example.dto.EventHeader;
import com.example.dto.EntityUpdate;
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
        
        // Convert EventBody
        if (request.hasEventBody()) {
            var protoBody = request.getEventBody();
            EventBody body = new EventBody();
            List<EntityUpdate> entities = new ArrayList<>();
            
            for (var protoEntity : protoBody.getEntitiesList()) {
                // Convert map<string, string> to map<string, object>
                Map<String, Object> updatedAttrs = new HashMap<>(protoEntity.getUpdatedAttributesMap());
                
                EntityUpdate entityUpdate = new EntityUpdate();
                entityUpdate.setEntityType(protoEntity.getEntityType());
                entityUpdate.setEntityId(protoEntity.getEntityId());
                entityUpdate.setUpdatedAttributes(updatedAttrs);
                
                entities.add(entityUpdate);
            }
            
            body.setEntities(entities);
            event.setEventBody(body);
        }
        
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

