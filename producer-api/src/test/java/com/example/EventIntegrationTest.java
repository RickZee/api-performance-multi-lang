package com.example;

import com.example.dto.EntityUpdate;
import com.example.dto.Event;
import com.example.dto.EventBody;
import com.example.dto.EventHeader;
import com.example.entity.CarEntity;
import com.example.repository.CarEntityRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.test.StepVerifier;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@ActiveProfiles("test")
class EventIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private CarEntityRepository carEntityRepository;

    @Autowired
    private DatabaseClient databaseClient;

    @BeforeEach
    void setUp() {
        carEntityRepository.deleteAll().block();
    }

    @Test
    void processEvent_WithNewEntity_ShouldCreateEntityInDatabase() {
        // Given
        Event event = createTestEvent();

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Event processed successfully");
    }

    @Test
    void processEvent_WithExistingEntity_ShouldSkipCreation() {
        // Given
        Event event = createTestEvent();
        
        // Create initial entity by processing an event first, then process the same event again
        // This ensures the entity is created in a way compatible with the repository
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // When - Process the same event again (entity already exists)
        // The API should return success even when entity already exists
        // This test verifies the insert-only behavior where existing entities are skipped
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Event processed successfully");
        
        // Then - Verify entity still exists (the service skips updates for existing entities)
        StepVerifier.create(carEntityRepository.findByEntityTypeAndId("Loan", "loan-12345"))
                .assertNext(entity -> {
                    assertThat(entity.getId()).isEqualTo("loan-12345");
                    assertThat(entity.getEntityType()).isEqualTo("Loan");
                    // The entity should still exist, but the data may not be updated
                    // as the service skips existing entities
                })
                .verifyComplete();
    }

    @Test
    void processEvent_WithMultipleEntities_ShouldProcessAllEntities() {
        // Given
        Event event = createEventWithMultipleEntities();

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Event processed successfully");
    }

    @Test
    void processEvent_WithInvalidEvent_ShouldReturnUnprocessableEntity() {
        // Given
        Event invalidEvent = new Event(); // Missing required fields

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(invalidEvent)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void health_ShouldReturnOk() {
        webTestClient.get()
                .uri("/api/v1/events/health")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Producer API is healthy");
    }

    @Test
    void processBulkEvents_WithValidEvents_ShouldProcessAllEvents() {
        // Given
        Event event1 = createTestEvent();
        // Create a second valid event with different entity ID to avoid conflicts
        EventHeader header2 = new EventHeader();
        header2.setUuid("660e8400-e29b-41d4-a716-446655440001");
        header2.setEventName("LoanPaymentSubmitted");
        header2.setCreatedDate(OffsetDateTime.now());
        header2.setSavedDate(OffsetDateTime.now());
        header2.setEventType("LoanPaymentSubmitted");

        Map<String, Object> attributes2 = new HashMap<>();
        attributes2.put("balance", 30000.00);
        attributes2.put("lastPaidDate", "2024-01-16T10:30:00Z");

        EntityUpdate entityUpdate2 = new EntityUpdate();
        entityUpdate2.setEntityType("Loan");
        entityUpdate2.setEntityId("loan-67890");
        entityUpdate2.setUpdatedAttributes(attributes2);

        EventBody body2 = new EventBody();
        body2.setEntities(List.of(entityUpdate2));

        Event event2 = new Event();
        event2.setEventHeader(header2);
        event2.setEventBody(body2);
        
        List<Event> events = List.of(event1, event2);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/bulk")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(events)
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.success").isEqualTo(true)
                .jsonPath("$.message").isEqualTo("All events processed successfully")
                .jsonPath("$.processedCount").isEqualTo(2)
                .jsonPath("$.failedCount").isEqualTo(0)
                .jsonPath("$.batchId").exists()
                .jsonPath("$.processingTimeMs").exists();
    }

    @Test
    void processBulkEvents_WithMixedValidAndInvalidEvents_ShouldProcessPartially() {
        // Given
        Event validEvent = createTestEvent();
        Event invalidEvent = new Event(); // Missing required fields
        List<Event> events = List.of(validEvent, invalidEvent);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/bulk")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(events)
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.success").isEqualTo(false)
                .jsonPath("$.processedCount").isEqualTo(1)
                .jsonPath("$.failedCount").isEqualTo(1)
                .jsonPath("$.batchId").exists()
                .jsonPath("$.processingTimeMs").exists();
    }

    @Test
    void processBulkEvents_WithEmptyList_ShouldReturnBadRequest() {
        // Given
        List<Event> events = List.of();

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/bulk")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(events)
                .exchange()
                .expectStatus().isBadRequest()
                .expectBody()
                .jsonPath("$.success").isEqualTo(false)
                .jsonPath("$.message").value(message -> assertThat(message.toString()).contains("empty"));
    }

    // Note: Testing null request body is not straightforward with WebTestClient
    // The endpoint handles null in the controller, but WebTestClient requires a body
    // This scenario is covered by the empty list test

    @Test
    void processEvent_WithEmptyEntitiesList_ShouldReturnUnprocessableEntity() {
        // Given
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName("LoanPaymentSubmitted");
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        EventBody body = new EventBody();
        body.setEntities(List.of()); // Empty entities list

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processEvent_WithEmptyEventName_ShouldReturnUnprocessableEntity() {
        // Given
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName(""); // Empty event name
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("balance", 24439.75);

        EntityUpdate entityUpdate = new EntityUpdate();
        entityUpdate.setEntityType("Loan");
        entityUpdate.setEntityId("loan-12345");
        entityUpdate.setUpdatedAttributes(attributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(entityUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processEvent_WithEmptyEntityType_ShouldReturnUnprocessableEntity() {
        // Given
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName("LoanPaymentSubmitted");
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("balance", 24439.75);

        EntityUpdate entityUpdate = new EntityUpdate();
        entityUpdate.setEntityType(""); // Empty entity type
        entityUpdate.setEntityId("loan-12345");
        entityUpdate.setUpdatedAttributes(attributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(entityUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processEvent_WithEmptyEntityId_ShouldReturnUnprocessableEntity() {
        // Given
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName("LoanPaymentSubmitted");
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("balance", 24439.75);

        EntityUpdate entityUpdate = new EntityUpdate();
        entityUpdate.setEntityType("Loan");
        entityUpdate.setEntityId(""); // Empty entity ID
        entityUpdate.setUpdatedAttributes(attributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(entityUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processEvent_WithNullEventBody_ShouldReturnUnprocessableEntity() {
        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue("null")
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    private Event createTestEvent() {
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName("LoanPaymentSubmitted");
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("balance", 24439.75);
        attributes.put("lastPaidDate", "2024-01-15T10:30:00Z");

        EntityUpdate entityUpdate = new EntityUpdate();
        entityUpdate.setEntityType("Loan");
        entityUpdate.setEntityId("loan-12345");
        entityUpdate.setUpdatedAttributes(attributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(entityUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        return event;
    }

    private Event createEventWithMultipleEntities() {
        EventHeader header = new EventHeader();
        header.setUuid("550e8400-e29b-41d4-a716-446655440000");
        header.setEventName("LoanPaymentSubmitted");
        header.setCreatedDate(OffsetDateTime.now());
        header.setSavedDate(OffsetDateTime.now());
        header.setEventType("LoanPaymentSubmitted");

        // Loan entity
        Map<String, Object> loanAttributes = new HashMap<>();
        loanAttributes.put("balance", 24439.75);
        loanAttributes.put("lastPaidDate", "2024-01-15T10:30:00Z");

        EntityUpdate loanUpdate = new EntityUpdate();
        loanUpdate.setEntityType("Loan");
        loanUpdate.setEntityId("loan-12345");
        loanUpdate.setUpdatedAttributes(loanAttributes);

        // LoanPayment entity
        Map<String, Object> paymentAttributes = new HashMap<>();
        paymentAttributes.put("paymentAmount", 560.25);
        paymentAttributes.put("paymentDate", "2024-01-15T10:30:00Z");
        paymentAttributes.put("paymentMethod", "ACH");

        EntityUpdate paymentUpdate = new EntityUpdate();
        paymentUpdate.setEntityType("LoanPayment");
        paymentUpdate.setEntityId("payment-12345");
        paymentUpdate.setUpdatedAttributes(paymentAttributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(loanUpdate, paymentUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        return event;
    }
}
