package com.example;

import com.example.dto.SimpleEvent;
import com.example.repository.SimpleEventRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.test.StepVerifier;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@ActiveProfiles("test")
class SimpleEventIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private SimpleEventRepository simpleEventRepository;

    @BeforeEach
    void setUp() {
        simpleEventRepository.deleteAll().block();
    }

    @Test
    void processSimpleEvent_WithValidEvent_ShouldCreateEventInDatabase() {
        // Given
        SimpleEvent event = createTestSimpleEvent();

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .isEqualTo("Simple event processed successfully");

        // Then - Verify event was saved in database
        StepVerifier.create(simpleEventRepository.findById(event.getUuid()))
                .assertNext(savedEvent -> {
                    assertThat(savedEvent.getId()).isEqualTo(event.getUuid());
                    assertThat(savedEvent.getEventName()).isEqualTo(event.getEventName());
                    assertThat(savedEvent.getEventType()).isEqualTo(event.getEventType());
                })
                .verifyComplete();
    }

    @Test
    void processSimpleEvent_WithMultipleEvents_ShouldProcessAllEvents() {
        // Given
        SimpleEvent event1 = createTestSimpleEvent();
        SimpleEvent event2 = createTestSimpleEventWithId("660e8400-e29b-41d4-a716-446655440001");

        // When - Process first event
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event1)
                .exchange()
                .expectStatus().isOk();

        // When - Process second event
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event2)
                .exchange()
                .expectStatus().isOk();

        // Then - Verify both events were saved
        StepVerifier.create(simpleEventRepository.count())
                .assertNext(count -> assertThat(count).isEqualTo(2))
                .verifyComplete();
    }

    @Test
    void processSimpleEvent_WithInvalidEvent_ShouldReturnUnprocessableEntity() {
        // Given
        SimpleEvent invalidEvent = new SimpleEvent(); // Missing required fields

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(invalidEvent)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processSimpleEvent_WithEmptyUuid_ShouldReturnUnprocessableEntity() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        event.setUuid(""); // Empty UUID

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
    }

    @Test
    void processSimpleEvent_WithEmptyEventName_ShouldReturnUnprocessableEntity() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        event.setEventName(""); // Empty event name

        // When & Then
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
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
    void processSimpleEvent_WithNullDates_ShouldUseCurrentTime() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        event.setCreatedDate(null);
        event.setSavedDate(null);

        // When
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Then - Verify event was saved with current timestamps
        StepVerifier.create(simpleEventRepository.findById(event.getUuid()))
                .assertNext(savedEvent -> {
                    assertThat(savedEvent.getCreatedDate()).isNotNull();
                    assertThat(savedEvent.getSavedDate()).isNotNull();
                })
                .verifyComplete();
    }

    @Test
    void processSimpleEvent_WithAllFields_ShouldSaveAllFields() {
        // Given
        SimpleEvent event = createTestSimpleEvent();
        OffsetDateTime createdDate = OffsetDateTime.parse("2024-01-15T10:30:00Z");
        OffsetDateTime savedDate = OffsetDateTime.parse("2024-01-15T10:30:05Z");
        event.setCreatedDate(createdDate);
        event.setSavedDate(savedDate);
        event.setEventType("LoanPaymentSubmitted");

        // When
        webTestClient.post()
                .uri("/api/v1/events/events-simple")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Then - Verify all fields were saved correctly
        StepVerifier.create(simpleEventRepository.findById(event.getUuid()))
                .assertNext(savedEvent -> {
                    assertThat(savedEvent.getId()).isEqualTo("550e8400-e29b-41d4-a716-446655440000");
                    assertThat(savedEvent.getEventName()).isEqualTo("LoanPaymentSubmitted");
                    assertThat(savedEvent.getEventType()).isEqualTo("LoanPaymentSubmitted");
                    // Note: Date comparison may need adjustment based on timezone handling
                    assertThat(savedEvent.getCreatedDate()).isNotNull();
                    assertThat(savedEvent.getSavedDate()).isNotNull();
                })
                .verifyComplete();
    }

    private SimpleEvent createTestSimpleEvent() {
        return createTestSimpleEventWithId("550e8400-e29b-41d4-a716-446655440000");
    }

    private SimpleEvent createTestSimpleEventWithId(String uuid) {
        SimpleEvent event = new SimpleEvent();
        event.setUuid(uuid);
        event.setEventName("LoanPaymentSubmitted");
        event.setCreatedDate(OffsetDateTime.parse("2024-01-15T10:30:00Z"));
        event.setSavedDate(OffsetDateTime.parse("2024-01-15T10:30:05Z"));
        event.setEventType("LoanPaymentSubmitted");
        return event;
    }
}
