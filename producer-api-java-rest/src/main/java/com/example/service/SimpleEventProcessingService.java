package com.example.service;

import com.example.constants.ApiConstants;
import com.example.dto.SimpleEvent;
import com.example.entity.SimpleEventEntity;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.concurrent.atomic.AtomicLong;

@Service
@RequiredArgsConstructor
@Slf4j
public class SimpleEventProcessingService {
    
    private final DatabaseClient databaseClient;
    private final AtomicLong persistedEventCount = new AtomicLong(0);

    public Mono<Void> processSimpleEvent(SimpleEvent event) {
        // Validate event structure
        if (event == null) {
            return Mono.error(new IllegalArgumentException("Event cannot be null"));
        }
        if (event.getUuid() == null || event.getUuid().trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("uuid is required and cannot be empty"));
        }
        if (event.getEventName() == null || event.getEventName().trim().isEmpty()) {
            return Mono.error(new IllegalArgumentException("eventName is required and cannot be empty"));
        }
        
        log.info("{} Processing simple event: {}", ApiConstants.API_NAME, event.getEventName());
        
        return saveSimpleEvent(event)
                .doOnNext(savedEvent -> {
                    log.info("{} Successfully saved simple event: {}", ApiConstants.API_NAME, savedEvent.getId());
                    logPersistedEventCount();
                })
                .then();
    }

    private void logPersistedEventCount() {
        long count = persistedEventCount.incrementAndGet();
        if (count % 10 == 0) {
            log.info("{} *** Persisted simple events count: {} ***", ApiConstants.API_NAME, count);
        }
    }

    private Mono<SimpleEventEntity> saveSimpleEvent(SimpleEvent event) {
        try {
            String id = event.getUuid();
            String eventName = event.getEventName();
            OffsetDateTime createdDate = event.getCreatedDate() != null ? event.getCreatedDate() : OffsetDateTime.now();
            OffsetDateTime savedDate = event.getSavedDate() != null ? event.getSavedDate() : OffsetDateTime.now();
            String eventType = event.getEventType();
            
            log.info("{} Saving simple event with ID: {}", ApiConstants.API_NAME, id);
            
            return databaseClient.sql("INSERT INTO simple_events (id, event_name, created_date, saved_date, event_type) VALUES (:id, :eventName, :createdDate, :savedDate, :eventType)")
                    .bind("id", id)
                    .bind("eventName", eventName)
                    .bind("createdDate", createdDate)
                    .bind("savedDate", savedDate)
                    .bind("eventType", eventType)
                    .fetch()
                    .rowsUpdated()
                    .then(Mono.just(new SimpleEventEntity(id, eventName, createdDate, savedDate, eventType)))
                    .doOnError(error -> log.error("{} Failed to save simple event: {}", ApiConstants.API_NAME, error.getMessage()));
        } catch (Exception e) {
            log.error("{} Error saving simple event", ApiConstants.API_NAME, e);
            return Mono.error(new RuntimeException("Error saving simple event", e));
        }
    }
}

