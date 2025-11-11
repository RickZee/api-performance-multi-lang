package com.example.controller;

import com.example.dto.EntityUpdate;
import com.example.dto.Event;
import com.example.dto.EventBody;
import com.example.dto.EventHeader;
import com.example.service.EventProcessingService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EventControllerTest {

    @Mock
    private EventProcessingService eventProcessingService;

    private WebTestClient webTestClient;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
        webTestClient = WebTestClient
                .bindToController(new EventController(eventProcessingService))
                .build();
    }

    @Test
    void processEvent_WithValidEvent_ShouldReturnSuccess() {
        // Given
        Event event = createTestEvent();
        when(eventProcessingService.processEvent(any(Event.class)))
                .thenReturn(Mono.empty());

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
    void processEvent_WithInvalidEvent_ShouldReturnBadRequest() {
        // Given
        Event invalidEvent = new Event(); // Missing required fields

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(invalidEvent)
                .exchange()
                .expectStatus().isBadRequest();
    }

    @Test
    void processEvent_WithServiceError_ShouldReturnInternalServerError() {
        // Given
        Event event = createTestEvent();
        when(eventProcessingService.processEvent(any(Event.class)))
                .thenReturn(Mono.error(new RuntimeException("Database error")));

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().is5xxServerError()
                .expectBody(String.class)
                .value(response -> response.contains("Error processing event"));
    }

    @Test
    void health_ShouldReturnOk() {
        // When & Then
        webTestClient.get()
                .uri("/api/v1/events/health")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Producer API is healthy");
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
}
