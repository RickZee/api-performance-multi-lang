package com.example.service;

import com.example.constants.ApiConstants;
import com.example.entity.CarEntity;
import com.example.repository.CarEntityRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

@Service
@RequiredArgsConstructor
@Slf4j
public class EventProcessingService {
    
    private final CarEntityRepository carEntityRepository;
    private final ObjectMapper objectMapper;
    private final DatabaseClient databaseClient;
    private final AtomicLong persistedEventCount = new AtomicLong(0);

    public Mono<Void> processEvent(String eventName, String entityType, String entityId, Map<String, String> updatedAttributes) {
        log.info("{} Processing event: {}", ApiConstants.API_NAME, eventName);
        
        return processEntityUpdate(entityType, entityId, updatedAttributes)
                .then();
    }

    private Mono<CarEntity> processEntityUpdate(String entityType, String entityId, Map<String, String> updatedAttributes) {
        return carEntityRepository.findByEntityTypeAndId(entityType, entityId)
                .flatMap(existingEntity -> updateExistingEntity(entityId, entityType, updatedAttributes, existingEntity))
                .switchIfEmpty(createNewEntity(entityId, entityType, updatedAttributes))
                .onErrorResume(org.springframework.dao.TransientDataAccessResourceException.class, 
                    error -> {
                        if (error.getMessage().contains("does not exist")) {
                            return createNewEntity(entityId, entityType, updatedAttributes);
                        }
                        return Mono.error(error);
                    });
    }

    private Mono<CarEntity> updateExistingEntity(String entityId, String entityType, Map<String, String> updatedAttributes, CarEntity existingEntity) {
        try {
            // Parse existing data
            var existingData = objectMapper.readTree(existingEntity.getData());
            
            // Update with new attributes
            updatedAttributes.forEach((key, value) -> {
                if (existingData.isObject()) {
                    ((com.fasterxml.jackson.databind.node.ObjectNode) existingData).set(key, objectMapper.valueToTree(value));
                }
            });
            
            // Create updated entity
            CarEntity updatedEntity = new CarEntity();
            updatedEntity.setId(existingEntity.getId());
            updatedEntity.setEntityType(existingEntity.getEntityType());
            updatedEntity.setCreatedAt(existingEntity.getCreatedAt());
            updatedEntity.setUpdatedAt(OffsetDateTime.now());
            updatedEntity.setData(existingData.toString());
            
            return carEntityRepository.save(updatedEntity)
                    .doOnNext(savedEntity -> {
                        log.info("{} Successfully updated entity: {}", ApiConstants.API_NAME, savedEntity.getId());
                        logPersistedEventCount();
                    });
        } catch (Exception e) {
            log.error("{} Error processing JSON for entity update", ApiConstants.API_NAME, e);
            return Mono.error(new RuntimeException("Error processing entity update", e));
        }
    }

    private Mono<CarEntity> createNewEntity(String entityId, String entityType, Map<String, String> updatedAttributes) {
        try {
            OffsetDateTime now = OffsetDateTime.now();
            String dataJson = objectMapper.writeValueAsString(updatedAttributes);
            
            log.info("{} Creating new entity with ID: {}", ApiConstants.API_NAME, entityId);
            
            return databaseClient.sql("INSERT INTO car_entities (id, entity_type, created_at, updated_at, data) VALUES (:id, :entityType, :createdAt, :updatedAt, :data)")
                    .bind("id", entityId)
                    .bind("entityType", entityType)
                    .bind("createdAt", now)
                    .bind("updatedAt", now)
                    .bind("data", dataJson)
                    .fetch()
                    .rowsUpdated()
                    .then(Mono.just(new CarEntity(entityId, entityType, now, now, dataJson)))
                    .doOnNext(savedEntity -> {
                        log.info("{} Successfully created entity: {}", ApiConstants.API_NAME, savedEntity.getId());
                        logPersistedEventCount();
                    })
                    .doOnError(error -> log.error("{} Failed to create entity: {}", ApiConstants.API_NAME, error.getMessage()));
        } catch (Exception e) {
            log.error("{} Error creating new entity", ApiConstants.API_NAME, e);
            return Mono.error(new RuntimeException("Error creating new entity", e));
        }
    }
    
    private void logPersistedEventCount() {
        long count = persistedEventCount.incrementAndGet();
        if (count % 10 == 0) {
            log.info("{} *** Persisted events count: {} ***", ApiConstants.API_NAME, count);
        }
    }
}
