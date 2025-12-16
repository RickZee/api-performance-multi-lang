package com.example.service;

import com.example.constants.ApiConstants;
import com.example.dto.Event;
import com.example.dto.Entity;
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
        var entities = event.getEntities();
        if (entities == null || entities.isEmpty()) {
            return Mono.error(new IllegalArgumentException("entities is required and cannot be empty"));
        }
        
        // Validate each entity
        for (var entity : entities) {
            if (entity.getEntityHeader() == null) {
                return Mono.error(new IllegalArgumentException("entityHeader is required"));
            }
            if (entity.getEntityHeader().getEntityType() == null || entity.getEntityHeader().getEntityType().trim().isEmpty()) {
                return Mono.error(new IllegalArgumentException("entityType cannot be empty"));
            }
            if (entity.getEntityHeader().getEntityId() == null || entity.getEntityHeader().getEntityId().trim().isEmpty()) {
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
                        .flatMap(entity -> processEntityUpdate(entity, eventId))
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

    private Mono<Void> processEntityUpdate(Entity entity, String eventId) {
        log.info("{} Processing entity for type: {} and id: {}",
                ApiConstants.API_NAME, entity.getEntityHeader().getEntityType(), entity.getEntityHeader().getEntityId());
        
        EntityRepository entityRepo = entityRepositoryFactory.getRepository(entity.getEntityHeader().getEntityType());
        if (entityRepo == null) {
            log.warn("{} Skipping entity with unknown type: {}",
                    ApiConstants.API_NAME, entity.getEntityHeader().getEntityType());
            return Mono.empty();
        }
        
        return entityRepo.existsByEntityId(entity.getEntityHeader().getEntityId(), null)
                .flatMap(exists -> {
                    if (exists) {
                        log.warn("{} Entity already exists, updating: {}",
                                ApiConstants.API_NAME, entity.getEntityHeader().getEntityId());
                        return updateExistingEntity(entityRepo, entity, eventId);
                    } else {
                        log.info("{} Entity does not exist, creating new: {}",
                                ApiConstants.API_NAME, entity.getEntityHeader().getEntityId());
                        return createNewEntity(entityRepo, entity, eventId);
                    }
                });
    }

    private Mono<Void> createNewEntity(EntityRepository entityRepo, Entity entity, String eventId) {
        String entityId = entity.getEntityHeader().getEntityId();
        String entityType = entity.getEntityHeader().getEntityType();
        OffsetDateTime now = OffsetDateTime.now();
        
        // Extract entity data from entity properties
        Map<String, Object> entityData = entity.getProperties();
        if (entityData == null) {
            entityData = new HashMap<>();
        }
        
        // Use createdAt and updatedAt from entityHeader
        OffsetDateTime createdAt = entity.getEntityHeader().getCreatedAt() != null 
                ? entity.getEntityHeader().getCreatedAt() 
                : now;
        OffsetDateTime updatedAt = entity.getEntityHeader().getUpdatedAt() != null 
                ? entity.getEntityHeader().getUpdatedAt() 
                : now;
        
        return entityRepo.create(entityId, entityType, createdAt, updatedAt, entityData, eventId, null)
                .doOnSuccess(v -> log.info("{} Successfully created entity: {}", ApiConstants.API_NAME, entityId));
    }

    private Mono<Void> updateExistingEntity(EntityRepository entityRepo, Entity entity, String eventId) {
        String entityId = entity.getEntityHeader().getEntityId();
        OffsetDateTime updatedAt = OffsetDateTime.now();
        
        // Extract entity data from entity properties
        Map<String, Object> entityData = entity.getProperties();
        if (entityData == null) {
            entityData = new HashMap<>();
        }
        
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
