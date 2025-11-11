package com.example.service;

import com.example.entity.CarEntity;
import com.example.repository.CarEntityRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.r2dbc.core.DatabaseClient;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EventProcessingServiceTest {

    @Mock
    private CarEntityRepository carEntityRepository;

    private EventProcessingService eventProcessingService;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
        DatabaseClient databaseClient = mock(DatabaseClient.class);
        eventProcessingService = new EventProcessingService(carEntityRepository, objectMapper, databaseClient);
    }

    @Test
    void processEvent_WithExistingEntity_ShouldUpdateEntity() {
        // Given
        String eventName = "LoanPaymentSubmitted";
        String entityType = "Loan";
        String entityId = "loan-12345";
        Map<String, String> updatedAttributes = new HashMap<>();
        updatedAttributes.put("balance", "24439.75");
        updatedAttributes.put("lastPaidDate", "2024-01-15T10:30:00Z");

        CarEntity existingEntity = new CarEntity();
        existingEntity.setId(entityId);
        existingEntity.setEntityType(entityType);
        existingEntity.setCreatedAt(OffsetDateTime.now().minusDays(1));
        existingEntity.setUpdatedAt(OffsetDateTime.now().minusDays(1));
        existingEntity.setData("{\"balance\": 25000.00, \"status\": \"active\"}");

        when(carEntityRepository.findByEntityTypeAndId(entityType, entityId))
                .thenReturn(Mono.just(existingEntity));
        when(carEntityRepository.save(any(CarEntity.class)))
                .thenReturn(Mono.just(existingEntity));

        // When & Then
        StepVerifier.create(eventProcessingService.processEvent(eventName, entityType, entityId, updatedAttributes))
                .verifyComplete();
    }

    @Test
    void processEvent_WithNonExistingEntity_ShouldCreateNewEntity() {
        // Given
        String eventName = "LoanCreated";
        String entityType = "Loan";
        String entityId = "loan-67890";
        Map<String, String> updatedAttributes = new HashMap<>();
        updatedAttributes.put("balance", "50000.00");
        updatedAttributes.put("status", "active");

        CarEntity newEntity = new CarEntity();
        newEntity.setId(entityId);
        newEntity.setEntityType(entityType);
        newEntity.setCreatedAt(OffsetDateTime.now());
        newEntity.setUpdatedAt(OffsetDateTime.now());
        newEntity.setData("{\"balance\": 50000.00, \"status\": \"active\"}");

        when(carEntityRepository.findByEntityTypeAndId(entityType, entityId))
                .thenReturn(Mono.error(new org.springframework.dao.TransientDataAccessResourceException("Entity does not exist")));
        when(carEntityRepository.save(any(CarEntity.class)))
                .thenReturn(Mono.just(newEntity));

        // When & Then
        StepVerifier.create(eventProcessingService.processEvent(eventName, entityType, entityId, updatedAttributes))
                .verifyComplete();
    }

    @Test
    void processEvent_WithDatabaseError_ShouldPropagateError() {
        // Given
        String eventName = "LoanPaymentSubmitted";
        String entityType = "Loan";
        String entityId = "loan-12345";
        Map<String, String> updatedAttributes = new HashMap<>();
        updatedAttributes.put("balance", "24439.75");

        when(carEntityRepository.findByEntityTypeAndId(entityType, entityId))
                .thenReturn(Mono.error(new RuntimeException("Database connection failed")));

        // When & Then
        StepVerifier.create(eventProcessingService.processEvent(eventName, entityType, entityId, updatedAttributes))
                .expectError(RuntimeException.class)
                .verify();
    }
}
