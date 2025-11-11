package com.example;

import ch.qos.logback.classic.Logger;
import com.example.constants.ApiConstants;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.example.dto.EntityUpdate;
import com.example.dto.Event;
import com.example.dto.EventBody;
import com.example.dto.EventHeader;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration tests for event logging functionality.
 * Verifies that all required log patterns are produced when processing events.
 * Connects to PostgreSQL database running in Docker.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
@ActiveProfiles("test")
class EventLoggingIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private DatabaseClient databaseClient;

    private ListAppender<ILoggingEvent> logAppender;

    @BeforeEach
    void setUp() {
        // Clean up database
        databaseClient.sql("DELETE FROM car_entities").fetch().rowsUpdated().block();

        // Set up log appender to capture logs
        Logger logger = (Logger) LoggerFactory.getLogger("com.example.service.EventProcessingService");
        logAppender = new ListAppender<>();
        logAppender.start();
        logger.addAppender(logAppender);
    }

    @Test
    void processEvent_ShouldLogProcessingEvent() {
        // Given
        Event event = createTestEvent("loan-log-test-001");

        // When
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Processing event" log with API name
        List<ILoggingEvent> processingLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Processing event:"))
                .collect(Collectors.toList());

        assertThat(processingLogs).isNotEmpty();
        assertThat(processingLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Processing event: LoanPaymentSubmitted");
    }

    @Test
    void processEvent_ShouldLogCreatingNewEntity() {
        // Given
        Event event = createTestEvent("loan-log-test-002");

        // When
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Creating new entity" log with API name
        List<ILoggingEvent> createLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Creating new entity with ID:"))
                .collect(Collectors.toList());

        assertThat(createLogs).isNotEmpty();
        assertThat(createLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Creating new entity with ID: loan-log-test-002");
    }

    @Test
    void processEvent_ShouldLogSuccessfullyCreatedEntity() {
        // Given
        Event event = createTestEvent("loan-log-test-003");

        // When
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Successfully created entity" log with API name
        List<ILoggingEvent> successLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Successfully created entity:"))
                .collect(Collectors.toList());

        assertThat(successLogs).isNotEmpty();
        assertThat(successLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Successfully created entity: loan-log-test-003");
    }

    @Test
    void processMultipleEvents_ShouldLogPersistedEventsCountEvery10Events() {
        // Given - Process 25 events
        for (int i = 1; i <= 25; i++) {
            Event event = createTestEvent("loan-log-bulk-" + i);
            webTestClient.post()
                    .uri("/api/v1/events")
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(event)
                    .exchange()
                    .expectStatus().isOk();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(200);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Persisted events count" logs appear at events 10, 20
        List<ILoggingEvent> countLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(countLogs.size()).isGreaterThanOrEqualTo(2);
        
        // Verify log format with API name
        boolean found10 = countLogs.stream()
                .anyMatch(log -> log.getFormattedMessage().contains("[producer-api-java-rest]") 
                        && log.getFormattedMessage().contains("Persisted events count: 10"));
        boolean found20 = countLogs.stream()
                .anyMatch(log -> log.getFormattedMessage().contains("[producer-api-java-rest]")
                        && log.getFormattedMessage().contains("Persisted events count: 20"));

        assertThat(found10).isTrue();
        assertThat(found20).isTrue();
    }

    @Test
    void processEvent_ShouldLogAllRequiredPatterns() {
        // Given
        Event event = createTestEvent("loan-log-complete-001");

        // When
        webTestClient.post()
                .uri("/api/v1/events")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(event)
                .exchange()
                .expectStatus().isOk();

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify all required log patterns are present with API name
        List<String> logMessages = logAppender.list.stream()
                .map(ILoggingEvent::getFormattedMessage)
                .collect(Collectors.toList());

        String allLogs = String.join("\n", logMessages);

        assertThat(allLogs).contains("[producer-api-java-rest]");
        assertThat(allLogs).contains("Processing event:");
        assertThat(allLogs).contains("Creating new entity with ID:");
        assertThat(allLogs).contains("Successfully created entity:");
    }

    private Event createTestEvent(String entityId) {
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
        entityUpdate.setEntityId(entityId);
        entityUpdate.setUpdatedAttributes(attributes);

        EventBody body = new EventBody();
        body.setEntities(List.of(entityUpdate));

        Event event = new Event();
        event.setEventHeader(header);
        event.setEventBody(body);

        return event;
    }
}

