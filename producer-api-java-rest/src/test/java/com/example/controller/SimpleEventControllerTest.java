package com.example.controller;

import com.example.dto.SimpleEvent;
import com.example.service.EventProcessingService;
import com.example.service.SimpleEventProcessingService;
import org.springframework.http.HttpStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.core.publisher.Mono;

import java.time.OffsetDateTime;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SimpleEventControllerTest {

    @Mock
    private EventProcessingService eventProcessingService;

    @Mock
    private SimpleEventProcessingService simpleEventProcessingService;

    private WebTestClient webTestClient;

    @BeforeEach
    void setUp() {
        webTestClient = WebTestClient
                .bindToController(new EventController(eventProcessingService, simpleEventProcessingService))
                .build();
    }

    @Test
    void processSimpleEvent_WithValidEvent_ShouldReturnSuccess() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        when(simpleEventProcessingService.processSimpleEvent(any(SimpleEvent.class)))
                .thenReturn(Mono.empty());

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Simple event processed successfully");
    }

    @Test
    void processSimpleEvent_WithInvalidEvent_ShouldReturnBadRequest() {
        // Given
        SimpleEvent invalidEvent = new SimpleEvent(); // Missing required fields

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(invalidEvent)
                .exchange()
                .expectStatus().isBadRequest();
    }

    @Test
    void processSimpleEvent_WithNullEvent_ShouldReturnUnprocessableEntity() {
        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue("null")
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY)
                .expectBody(String.class)
                .value(response -> response.contains("Event body is required"));
    }

    @Test
    void processSimpleEvent_WithServiceError_ShouldReturnInternalServerError() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        when(simpleEventProcessingService.processSimpleEvent(any(SimpleEvent.class)))
                .thenReturn(Mono.error(new RuntimeException("Database error")));

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().is5xxServerError()
                .expectBody(String.class)
                .value(response -> response.contains("Error processing event"));
    }

    @Test
    void processSimpleEvent_WithValidationError_ShouldReturnUnprocessableEntity() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        when(simpleEventProcessingService.processSimpleEvent(any(SimpleEvent.class)))
                .thenReturn(Mono.error(new IllegalArgumentException("uuid is required")));

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY)
                .expectBody(String.class)
                .value(response -> response.contains("Invalid event"));
    }

    private SimpleEvent createTestSimpleEvent() {
        SimpleEvent event = new SimpleEvent();
        event.setUuid("550e8400-e29b-41d4-a716-446655440000");
        event.setEventName("LoanPaymentSubmitted");
        event.setCreatedDate(OffsetDateTime.now());
        event.setSavedDate(OffsetDateTime.now());
        event.setEventType("LoanPaymentSubmitted");
        return event;
    }
}
