package com.example.repository;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.Map;

@Repository
@RequiredArgsConstructor
@Slf4j
public class EventHeaderRepository {
    
    private final DatabaseClient databaseClient;
    private final ObjectMapper objectMapper;

    public Mono<Void> create(
            String eventId,
            String eventName,
            String eventType,
            OffsetDateTime createdDate,
            OffsetDateTime savedDate,
            Map<String, Object> headerData,
            DatabaseClient.GenericExecuteSpec executeSpec
    ) {
        try {
            String headerDataJson = objectMapper.writeValueAsString(headerData);
            
            var spec = executeSpec != null ? executeSpec : databaseClient.sql(
                    "INSERT INTO event_headers (id, event_name, event_type, created_date, saved_date, header_data) " +
                    "VALUES (:id, :eventName, :eventType, :createdDate, :savedDate, :headerData::jsonb)"
            );
            
            return spec
                    .bind("id", eventId)
                    .bind("eventName", eventName)
                    .bind("eventType", eventType)
                    .bind("createdDate", createdDate)
                    .bind("savedDate", savedDate)
                    .bind("headerData", headerDataJson)
                    .fetch()
                    .rowsUpdated()
                    .then()
                    .onErrorMap(org.springframework.dao.DataIntegrityViolationException.class, e -> {
                        // Check if it's a unique violation
                        if (e.getMessage() != null && e.getMessage().contains("duplicate key")) {
                            log.warn("Duplicate event header ID detected: {}", eventId);
                            return new DuplicateEventError(eventId, null);
                        }
                        return e;
                    });
        } catch (Exception e) {
            log.error("Error serializing header data", e);
            return Mono.error(new RuntimeException("Failed to serialize header data", e));
        }
    }
}

