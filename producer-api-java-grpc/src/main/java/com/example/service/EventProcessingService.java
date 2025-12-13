package com.example.service;

import com.example.constants.ApiConstants;
import com.example.dto.Event;
import com.example.dto.EntityUpdate;
import com.example.repository.BusinessEventRepository;
import com.example.repository.DuplicateEventError;
import com.example.repository.EntityRepository;
import com.example.repository.EntityRepositoryFactory;
import com.example.repository.EventHeaderRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;

@Service
@RequiredArgsConstructor
@Slf4j
public class EventProcessingService {
    
    private final BusinessEventRepository businessEventRepository;
    private final EventHeaderRepository eventHeaderRepository;
    private final EntityRepositoryFactory entityRepositoryFactory;
    private final DatabaseClient databaseClient;
    private final ObjectMapper objectMapper;
    private final AtomicLong persistedEventCount = new AtomicLong(0);

    @Transactional
    public Mono<Void> processEvent(Event event) {
        // Validate event structure
        if (event == null) {
            return Mono.error(new IllegalArgumentException("Event cannot be null"));
        }
        if (event.getEventHeader() == null) {
            return Mono.error(new IllegalArgumentException("eventHeader is required"));
        }
        String eventName = event.getEventHeader().getEventName();
        if (eventName == null || eventName.trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("eventName is required and cannot be empty"));
        }
        if (event.getEventBody() == null) {
            return Mono.error(new IllegalArgumentException("eventBody is required"));
        }
        var entities = event.getEventBody().getEntities();
        if (entities == null || entities.isEmpty()) {
            return Mono.error(new IllegalArgumentException("eventBody.entities is required and cannot be empty"));
        }
        
        // Validate each entity
        for (var entity : entities) {
            if (entity.getEntityType() == null || entity.getEntityType().trim().isEmpty()) {
                return Mono.error(new IllegalArgumentException("entityType cannot be empty"));
            }
            if (entity.getEntityId() == null || entity.getEntityId().trim().isEmpty()) {
                return Mono.error(new IllegalArgumentException("entityId cannot be empty"));
            }
        }
        
        log.info("{} Processing event: {}", ApiConstants.API_NAME, eventName);
        
        // Generate event ID if not provided
        final String eventId = event.getEventHeader().getUuid() != null && !event.getEventHeader().getUuid().trim().isEmpty()
                ? event.getEventHeader().getUuid()
                : "event-" + OffsetDateTime.now().toString();
        
        // Process event - all operations will be in a transaction due to @Transactional
        // Add timeout to ensure the operation completes within 55 seconds (before client timeout of 60s)
        return saveBusinessEvent(event, eventId)
                .then(saveEventHeader(event, eventId))
                .then(Flux.fromIterable(entities)
                        .flatMap(entityUpdate -> processEntityUpdate(entityUpdate, eventId))
                        .then())
                .timeout(Duration.ofSeconds(55))
                .doOnSuccess(v -> {
                    logPersistedEventCount();
                    log.info("{} Successfully processed event in transaction: {}", ApiConstants.API_NAME, eventId);
                })
                .doOnError(error -> {
                    if (error instanceof TimeoutException) {
                        log.error("{} Event processing timed out after 55 seconds: {}", ApiConstants.API_NAME, eventId, error);
                    } else {
                        log.error("{} Error processing event in transaction: {}", ApiConstants.API_NAME, error.getMessage(), error);
                    }
                })
                .onErrorMap(DuplicateEventError.class, e -> e)
                .onErrorMap(TimeoutException.class, e -> {
                    log.error("{} Event processing timeout for event: {}", ApiConstants.API_NAME, eventId);
                    return new RuntimeException("Event processing timed out after 55 seconds", e);
                });
    }

    private Mono<Void> saveBusinessEvent(Event event, String eventId) {
        String eventName = event.getEventHeader().getEventName();
        String eventType = event.getEventHeader().getEventType();
        OffsetDateTime createdDate = event.getEventHeader().getCreatedDate();
        OffsetDateTime savedDate = event.getEventHeader().getSavedDate();
        
        // Use current time if dates are not provided
        OffsetDateTime now = OffsetDateTime.now();
        if (createdDate == null) {
            createdDate = now;
        }
        if (savedDate == null) {
            savedDate = now;
        }
        
        // Convert event to map for JSONB storage
        try {
            String eventJson = objectMapper.writeValueAsString(event);
            @SuppressWarnings("unchecked")
            Map<String, Object> eventData = objectMapper.readValue(eventJson, Map.class);
            
            return businessEventRepository.create(
                    eventId, eventName, eventType, createdDate, savedDate, eventData, null
            )
            .doOnSuccess(v -> log.info("{} Successfully saved business event: {}", ApiConstants.API_NAME, eventId))
            .onErrorMap(DuplicateEventError.class, e -> e);
        } catch (Exception e) {
            log.error("{} Error serializing event", ApiConstants.API_NAME, e);
            return Mono.error(new RuntimeException("Failed to serialize event", e));
        }
    }

    private Mono<Void> saveEventHeader(Event event, String eventId) {
        String eventName = event.getEventHeader().getEventName();
        String eventType = event.getEventHeader().getEventType();
        OffsetDateTime createdDate = event.getEventHeader().getCreatedDate();
        OffsetDateTime savedDate = event.getEventHeader().getSavedDate();
        
        // Use current time if dates are not provided
        OffsetDateTime now = OffsetDateTime.now();
        if (createdDate == null) {
            createdDate = now;
        }
        if (savedDate == null) {
            savedDate = now;
        }
        
        // Convert eventHeader to map for JSONB storage
        try {
            String headerJson = objectMapper.writeValueAsString(event.getEventHeader());
            @SuppressWarnings("unchecked")
            Map<String, Object> headerData = objectMapper.readValue(headerJson, Map.class);
            
            return eventHeaderRepository.create(
                    eventId, eventName, eventType, createdDate, savedDate, headerData, null
            )
            .doOnSuccess(v -> log.info("{} Successfully saved event header: {}", ApiConstants.API_NAME, eventId))
            .onErrorMap(DuplicateEventError.class, e -> e);
        } catch (Exception e) {
            log.error("{} Error serializing event header", ApiConstants.API_NAME, e);
            return Mono.error(new RuntimeException("Failed to serialize event header", e));
        }
    }

    private Mono<Void> processEntityUpdate(EntityUpdate entityUpdate, String eventId) {
        log.info("{} Processing entity for type: {} and id: {}",
                ApiConstants.API_NAME, entityUpdate.getEntityType(), entityUpdate.getEntityId());
        
        EntityRepository entityRepo = entityRepositoryFactory.getRepository(entityUpdate.getEntityType());
        if (entityRepo == null) {
            log.warn("{} Skipping entity with unknown type: {}",
                    ApiConstants.API_NAME, entityUpdate.getEntityType());
            return Mono.empty();
        }
        
        return entityRepo.existsByEntityId(entityUpdate.getEntityId(), null)
                .flatMap(exists -> {
                    if (exists) {
                        log.warn("{} Entity already exists, updating: {}",
                                ApiConstants.API_NAME, entityUpdate.getEntityId());
                        return updateExistingEntity(entityRepo, entityUpdate, eventId);
                    } else {
                        log.info("{} Entity does not exist, creating new: {}",
                                ApiConstants.API_NAME, entityUpdate.getEntityId());
                        return createNewEntity(entityRepo, entityUpdate, eventId);
                    }
                });
    }

    private Mono<Void> createNewEntity(EntityRepository entityRepo, EntityUpdate entityUpdate, String eventId) {
        String entityId = entityUpdate.getEntityId();
        String entityType = entityUpdate.getEntityType();
        OffsetDateTime now = OffsetDateTime.now();
        
        // Extract entity data from updatedAttributes
        Map<String, Object> updatedAttrs = entityUpdate.getUpdatedAttributes();
        if (updatedAttrs == null) {
            updatedAttrs = new HashMap<>();
        }
        
        // Make a copy to avoid modifying the original
        Map<String, Object> entityData = new HashMap<>(updatedAttrs);
        
        // Remove entityHeader from entity_data if it exists (nested structure)
        Object entityHeaderObj = entityData.remove("entityHeader");
        if (entityHeaderObj == null) {
            entityHeaderObj = entityData.remove("entity_header");
        }
        
        // Extract createdAt and updatedAt from entityHeader if present, otherwise from entity_data, otherwise use now
        OffsetDateTime createdAt = now;
        OffsetDateTime updatedAt = now;
        
        if (entityHeaderObj instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> entityHeader = (Map<String, Object>) entityHeaderObj;
            createdAt = parseDateTime(entityHeader.get("createdAt"), entityHeader.get("created_at"), now);
            updatedAt = parseDateTime(entityHeader.get("updatedAt"), entityHeader.get("updated_at"), now);
        }
        
        // Try to get from entity_data if not found in entityHeader
        if (createdAt.equals(now)) {
            Object ca = entityData.remove("createdAt");
            if (ca == null) {
                ca = entityData.remove("created_at");
            }
            createdAt = parseDateTime(ca, null, now);
        }
        if (updatedAt.equals(now)) {
            Object ua = entityData.remove("updatedAt");
            if (ua == null) {
                ua = entityData.remove("updated_at");
            }
            updatedAt = parseDateTime(ua, null, now);
        }
        
        return entityRepo.create(entityId, entityType, createdAt, updatedAt, entityData, eventId, null)
                .doOnSuccess(v -> log.info("{} Successfully created entity: {}", ApiConstants.API_NAME, entityId));
    }

    private Mono<Void> updateExistingEntity(EntityRepository entityRepo, EntityUpdate entityUpdate, String eventId) {
        String entityId = entityUpdate.getEntityId();
        OffsetDateTime updatedAt = OffsetDateTime.now();
        
        // Extract entity data from updatedAttributes
        Map<String, Object> updatedAttrs = entityUpdate.getUpdatedAttributes();
        if (updatedAttrs == null) {
            updatedAttrs = new HashMap<>();
        }
        
        // Make a copy to avoid modifying the original
        Map<String, Object> entityData = new HashMap<>(updatedAttrs);
        
        // Remove entityHeader from entity_data if it exists
        entityData.remove("entityHeader");
        entityData.remove("entity_header");
        
        // Remove entityHeader fields that might be at top level
        entityData.remove("createdAt");
        entityData.remove("created_at");
        entityData.remove("updatedAt");
        entityData.remove("updated_at");
        
        return entityRepo.update(entityId, updatedAt, entityData, eventId, null)
                .doOnSuccess(v -> log.info("{} Successfully updated entity: {}", ApiConstants.API_NAME, entityId));
    }

    private OffsetDateTime parseDateTime(Object value1, Object value2, OffsetDateTime defaultValue) {
        if (value1 != null) {
            try {
                if (value1 instanceof OffsetDateTime) {
                    return (OffsetDateTime) value1;
                }
                if (value1 instanceof String) {
                    return OffsetDateTime.parse((String) value1);
                }
            } catch (Exception e) {
                // Ignore parsing errors
            }
        }
        if (value2 != null) {
            try {
                if (value2 instanceof OffsetDateTime) {
                    return (OffsetDateTime) value2;
                }
                if (value2 instanceof String) {
                    return OffsetDateTime.parse((String) value2);
                }
            } catch (Exception e) {
                // Ignore parsing errors
            }
        }
        return defaultValue;
    }

    private void logPersistedEventCount() {
        long count = persistedEventCount.incrementAndGet();
        if (count % 10 == 0) {
            log.info("{} *** Persisted events count: {} ***", ApiConstants.API_NAME, count);
        }
    }
}
