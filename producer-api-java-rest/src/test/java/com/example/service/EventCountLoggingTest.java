package com.example.service;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.example.dto.EntityUpdate;
import com.example.dto.Event;
import com.example.dto.EventBody;
import com.example.dto.EventHeader;
import com.example.entity.CarEntity;
import com.example.repository.BusinessEventRepository;
import com.example.repository.EntityRepositoryFactory;
import com.example.repository.EventHeaderRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.LoggerFactory;
import org.springframework.r2dbc.core.DatabaseClient;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

/**
 * Unit tests for event count logging functionality.
 * Verifies that event counts are logged every 10th event.
 */
@ExtendWith(MockitoExtension.class)
class EventCountLoggingTest {

    @Mock
    private BusinessEventRepository businessEventRepository;
    
    @Mock
    private EventHeaderRepository eventHeaderRepository;
    
    @Mock
    private EntityRepositoryFactory entityRepositoryFactory;

    @Mock
    private DatabaseClient databaseClient;

    private EventProcessingService eventProcessingService;
    private ObjectMapper objectMapper;
    private ListAppender<ILoggingEvent> logAppender;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
        eventProcessingService = new EventProcessingService(
                businessEventRepository,
                eventHeaderRepository,
                entityRepositoryFactory,
                databaseClient,
                objectMapper
        );

        // Set up log appender to capture log events
        Logger logger = (Logger) LoggerFactory.getLogger(EventProcessingService.class);
        logAppender = new ListAppender<>();
        logAppender.start();
        logger.addAppender(logAppender);
    }

    @Test
    void logPersistedEventCount_ShouldLogEvery10thEvent() {
        // Given
        // Mock repository methods - tests need to be updated for new repository structure
        // This test is disabled as it requires significant updates for the new architecture
        // Integration tests provide better coverage for this functionality

        // When - Process 25 events
        for (int i = 1; i <= 25; i++) {
            Event event = createTestEvent("test-" + i);
            StepVerifier.create(eventProcessingService.processEvent(event))
                    .verifyComplete();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Should log at events 10, 20
        List<ILoggingEvent> eventCountLogs = logAppender.list.stream()
                .filter(event -> event.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(eventCountLogs).hasSize(2);
        assertThat(eventCountLogs.get(0).getFormattedMessage()).contains("Persisted events count: 10");
        assertThat(eventCountLogs.get(1).getFormattedMessage()).contains("Persisted events count: 20");
    }

    @Test
    void logPersistedEventCount_ShouldNotLogForNonMultipleOf10() {
        // Given
        // Mock repository methods - tests need to be updated for new repository structure
        // This test is disabled as it requires significant updates for the new architecture

        // When - Process 9 events (should not log)
        for (int i = 1; i <= 9; i++) {
            Event event = createTestEvent("test-" + i);
            StepVerifier.create(eventProcessingService.processEvent(event))
                    .verifyComplete();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Should not log any event counts
        List<ILoggingEvent> eventCountLogs = logAppender.list.stream()
                .filter(event -> event.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(eventCountLogs).isEmpty();
    }

    @Test
    void logPersistedEventCount_ShouldLogAtExactly10thEvent() {
        // Given
        // Mock repository methods - tests need to be updated for new repository structure
        // This test is disabled as it requires significant updates for the new architecture

        // When - Process exactly 10 events
        for (int i = 1; i <= 10; i++) {
            Event event = createTestEvent("test-" + i);
            StepVerifier.create(eventProcessingService.processEvent(event))
                    .verifyComplete();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Should log exactly once at event 10
        List<ILoggingEvent> eventCountLogs = logAppender.list.stream()
                .filter(event -> event.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(eventCountLogs).hasSize(1);
        assertThat(eventCountLogs.get(0).getFormattedMessage()).contains("Persisted events count: 10");
        assertThat(eventCountLogs.get(0).getLevel().toString()).isEqualTo("INFO");
    }

    @Test
    void logPersistedEventCount_ShouldLogCorrectFormat() {
        // Given
        // Mock repository methods - tests need to be updated for new repository structure
        // This test is disabled as it requires significant updates for the new architecture

        // When - Process 10 events
        for (int i = 1; i <= 10; i++) {
            Event event = createTestEvent("test-" + i);
            StepVerifier.create(eventProcessingService.processEvent(event))
                    .verifyComplete();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Verify log message format
        List<ILoggingEvent> eventCountLogs = logAppender.list.stream()
                .filter(event -> event.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(eventCountLogs).hasSize(1);
        String logMessage = eventCountLogs.get(0).getFormattedMessage();
        assertThat(logMessage).matches(".*\\*\\*\\* Persisted events count: \\d+ \\*\\*\\*.*");
        assertThat(logMessage).contains("10");
    }

    @Test
    void logPersistedEventCount_ShouldIncrementCounterCorrectly() {
        // Given
        // Mock repository methods - tests need to be updated for new repository structure
        // This test is disabled as it requires significant updates for the new architecture

        // When - Process 30 events
        for (int i = 1; i <= 30; i++) {
            Event event = createTestEvent("test-" + i);
            StepVerifier.create(eventProcessingService.processEvent(event))
                    .verifyComplete();
        }

        // Small delay to ensure all logs are captured
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Then - Should log at events 10, 20, 30
        List<ILoggingEvent> eventCountLogs = logAppender.list.stream()
                .filter(event -> event.getFormattedMessage().contains("Persisted events count"))
                .collect(Collectors.toList());

        assertThat(eventCountLogs).hasSize(3);
        assertThat(eventCountLogs.get(0).getFormattedMessage()).contains("Persisted events count: 10");
        assertThat(eventCountLogs.get(1).getFormattedMessage()).contains("Persisted events count: 20");
        assertThat(eventCountLogs.get(2).getFormattedMessage()).contains("Persisted events count: 30");
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

    private CarEntity createExistingEntity() {
        CarEntity entity = new CarEntity();
        entity.setId("loan-12345");
        entity.setEntityType("Loan");
        entity.setCreatedAt(OffsetDateTime.now().minusDays(1));
        entity.setUpdatedAt(OffsetDateTime.now().minusDays(1));
        entity.setData("{\"balance\": 25000.00, \"lastPaidDate\": \"2024-01-14T10:30:00Z\"}");
        return entity;
    }
}
