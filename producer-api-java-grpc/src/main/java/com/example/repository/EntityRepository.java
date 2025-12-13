package com.example.repository;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.Map;

@Slf4j
public class EntityRepository {
    
    private final DatabaseClient databaseClient;
    private final ObjectMapper objectMapper;
    private final String tableName;

    public EntityRepository(DatabaseClient databaseClient, ObjectMapper objectMapper, String tableName) {
        this.databaseClient = databaseClient;
        this.objectMapper = objectMapper;
        this.tableName = tableName;
    }

    public String getTableName() {
        return tableName;
    }

    public Mono<Boolean> existsByEntityId(String entityId, DatabaseClient.GenericExecuteSpec executeSpec) {
        // Use positional parameters - R2DBC supports both named and positional, but positional is more reliable
        String query = "SELECT EXISTS(SELECT 1 FROM " + tableName + " WHERE entity_id = $1)";
        
        // Always use databaseClient - transactions are handled by Spring's @Transactional
        // The executeSpec parameter is kept for future use if we need explicit transaction control
        return databaseClient.sql(query)
                .bind(0, entityId)
                .map((row, metadata) -> {
                    Object value = row.get(0);
                    if (value instanceof Boolean) {
                        return (Boolean) value;
                    }
                    // Handle case where EXISTS returns a different type
                    return Boolean.TRUE.equals(value);
                })
                .one()
                .defaultIfEmpty(false);
    }

    public Mono<Void> create(
            String entityId,
            String entityType,
            OffsetDateTime createdAt,
            OffsetDateTime updatedAt,
            Map<String, Object> entityData,
            String eventId,
            DatabaseClient.GenericExecuteSpec executeSpec
    ) {
        try {
            String entityDataJson = objectMapper.writeValueAsString(entityData);
            
            var spec = executeSpec != null ? executeSpec : databaseClient.sql(
                    "INSERT INTO " + tableName + " (entity_id, entity_type, created_at, updated_at, entity_data, event_id) " +
                    "VALUES (:entityId, :entityType, :createdAt, :updatedAt, :entityData::jsonb, :eventId)"
            );
            
            return spec
                    .bind("entityId", entityId)
                    .bind("entityType", entityType)
                    .bind("createdAt", createdAt)
                    .bind("updatedAt", updatedAt)
                    .bind("entityData", entityDataJson)
                    .bind("eventId", eventId)
                    .fetch()
                    .rowsUpdated()
                    .then();
        } catch (Exception e) {
            log.error("Error serializing entity data", e);
            return Mono.error(new RuntimeException("Failed to serialize entity data", e));
        }
    }

    public Mono<Void> update(
            String entityId,
            OffsetDateTime updatedAt,
            Map<String, Object> entityData,
            String eventId,
            DatabaseClient.GenericExecuteSpec executeSpec
    ) {
        try {
            String entityDataJson = objectMapper.writeValueAsString(entityData);
            
            var spec = executeSpec != null ? executeSpec : databaseClient.sql(
                    "UPDATE " + tableName + " " +
                    "SET updated_at = :updatedAt, entity_data = :entityData::jsonb, event_id = :eventId " +
                    "WHERE entity_id = :entityId"
            );
            
            return spec
                    .bind("updatedAt", updatedAt)
                    .bind("entityData", entityDataJson)
                    .bind("eventId", eventId)
                    .bind("entityId", entityId)
                    .fetch()
                    .rowsUpdated()
                    .then();
        } catch (Exception e) {
            log.error("Error serializing entity data", e);
            return Mono.error(new RuntimeException("Failed to serialize entity data", e));
        }
    }
}

