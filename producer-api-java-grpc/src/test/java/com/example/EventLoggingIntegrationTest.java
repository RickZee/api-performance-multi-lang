package com.example;

import ch.qos.logback.classic.Logger;
import com.example.constants.ApiConstants;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.example.grpc.*;
import com.example.repository.CarEntityRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.ActiveProfiles;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration tests for gRPC event logging functionality.
 * Verifies that all required log patterns are produced when processing events via gRPC.
 * Connects to PostgreSQL database running in Docker.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = {
        "grpc.server.port=-1"  // Disable gRPC server port binding
    }
)
@ActiveProfiles("test")
class EventLoggingIntegrationTest {

    @Autowired
    private DatabaseClient databaseClient;

    @Autowired
    private EventServiceImpl eventService;

    private ListAppender<ILoggingEvent> logAppender;

    @BeforeEach
    void setUp() {
        // Clean up database
        databaseClient.sql("DELETE FROM car_entities").fetch().rowsUpdated().block();

        // Set up log appender to capture logs from both services
        Logger eventServiceLogger = (Logger) LoggerFactory.getLogger("com.example.grpc.EventServiceImpl");
        Logger processingServiceLogger = (Logger) LoggerFactory.getLogger("com.example.service.EventProcessingService");
        
        logAppender = new ListAppender<>();
        logAppender.start();
        eventServiceLogger.addAppender(logAppender);
        processingServiceLogger.addAppender(logAppender);
    }

    @Test
    void processEvent_ShouldLogReceivedGrpcEvent() {
        // Given
        EventRequest request = createValidEventRequest("loan-grpc-log-001");
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Received gRPC event" log
        List<ILoggingEvent> receivedLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Received gRPC event:"))
                .collect(Collectors.toList());

        assertThat(receivedLogs).isNotEmpty();
        assertThat(receivedLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Received gRPC event: LoanPaymentSubmitted");
    }

    @Test
    void processEvent_ShouldLogProcessingEvent() {
        // Given
        EventRequest request = createValidEventRequest("loan-grpc-log-002");
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Processing event" log
        List<ILoggingEvent> processingLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Processing event:"))
                .collect(Collectors.toList());

        assertThat(processingLogs).isNotEmpty();
        assertThat(processingLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Processing event:");
    }

    @Test
    void processEvent_ShouldLogCreatingNewEntity() {
        // Given
        EventRequest request = createValidEventRequest("loan-grpc-log-003");
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Creating new entity" log
        List<ILoggingEvent> createLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Creating new entity with ID:"))
                .collect(Collectors.toList());

        assertThat(createLogs).isNotEmpty();
        assertThat(createLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Creating new entity with ID: loan-grpc-log-003");
    }

    @Test
    void processEvent_ShouldLogSuccessfullyCreatedEntity() {
        // Given
        EventRequest request = createValidEventRequest("loan-grpc-log-004");
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify "Successfully created entity" log
        List<ILoggingEvent> successLogs = logAppender.list.stream()
                .filter(log -> log.getFormattedMessage().contains("Successfully created entity:"))
                .collect(Collectors.toList());

        assertThat(successLogs).isNotEmpty();
        assertThat(successLogs.get(0).getFormattedMessage())
                .contains(ApiConstants.API_NAME)
                .contains("Successfully created entity: loan-grpc-log-004");
    }

    @Test
    void processMultipleEvents_ShouldLogPersistedEventsCountEvery10Events() {
        // Given - Process 25 events
        for (int i = 1; i <= 25; i++) {
            EventRequest request = createValidEventRequest("loan-grpc-bulk-" + i);
            TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();
            eventService.processEvent(request, responseObserver);
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
                .anyMatch(log -> log.getFormattedMessage().contains("[producer-api-java-grpc]")
                        && log.getFormattedMessage().contains("Persisted events count: 10"));
        boolean found20 = countLogs.stream()
                .anyMatch(log -> log.getFormattedMessage().contains("[producer-api-java-grpc]")
                        && log.getFormattedMessage().contains("Persisted events count: 20"));

        assertThat(found10).isTrue();
        assertThat(found20).isTrue();
    }

    @Test
    void processEvent_ShouldLogAllRequiredPatterns() {
        // Given
        EventRequest request = createValidEventRequest("loan-grpc-complete-001");
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Small delay to ensure logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify all required log patterns are present
        List<String> logMessages = logAppender.list.stream()
                .map(ILoggingEvent::getFormattedMessage)
                .collect(Collectors.toList());

        String allLogs = String.join("\n", logMessages);

        assertThat(allLogs).contains("[producer-api-java-grpc]");
        assertThat(allLogs).contains("Received gRPC event:");
        assertThat(allLogs).contains("Processing event:");
        assertThat(allLogs).contains("Creating new entity with ID:");
        assertThat(allLogs).contains("Successfully created entity:");
    }

    private EventRequest createValidEventRequest(String entityId) {
        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanPaymentSubmitted")
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:00Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        Map<String, String> attributes = new HashMap<>();
        attributes.put("balance", "24439.75");
        attributes.put("lastPaidDate", "2024-01-15T10:30:00Z");

        EntityUpdate entityUpdate = EntityUpdate.newBuilder()
                .setEntityType("Loan")
                .setEntityId(entityId)
                .putAllUpdatedAttributes(attributes)
                .build();

        EventBody body = EventBody.newBuilder()
                .addEntities(entityUpdate)
                .build();

        return EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();
    }
}

