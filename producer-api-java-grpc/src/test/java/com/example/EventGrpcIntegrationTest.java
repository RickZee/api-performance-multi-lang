package com.example;

import com.example.entity.CarEntity;
import com.example.grpc.*;
import com.example.repository.CarEntityRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.ActiveProfiles;
import reactor.test.StepVerifier;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.NONE,
    properties = {
        "grpc.server.port=-1"  // Disable gRPC server port binding
    }
)
@ActiveProfiles("test")
class EventGrpcIntegrationTest {

    @Autowired
    private CarEntityRepository carEntityRepository;

    @Autowired
    private DatabaseClient databaseClient;

    @Autowired
    private EventServiceImpl eventService;

    @BeforeEach
    void setUp() {
        // Clean up database
        databaseClient.sql("DELETE FROM car_entities").fetch().rowsUpdated().block();
    }

    @Test
    void processEvent_WithValidEvent_ShouldProcessSuccessfully() {
        // Given
        EventRequest request = createValidEventRequest();
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getMessage()).isEqualTo("Event processed successfully");

        // Verify entity was created in database
        StepVerifier.create(carEntityRepository.findByEntityTypeAndId("Loan", "loan-12345"))
                .assertNext(entity -> {
                    assertThat(entity.getEntityType()).isEqualTo("Loan");
                    assertThat(entity.getId()).isEqualTo("loan-12345");
                    assertThat(entity.getData()).contains("24439.75");
                })
                .verifyComplete();
    }

    @Test
    void processEvent_WithInvalidEvent_ShouldReturnError() {
        // Given - Create request with empty event name (proto3 returns default instances, not null)
        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(EventHeader.newBuilder().setEventName("").build()) // Empty event name
                .setEventBody(EventBody.newBuilder().build()) // Empty entities list
                .build();
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getMessage()).contains("Invalid event");
    }

    @Test
    void processEvent_WithExistingEntity_ShouldUpdateEntity() {
        // Given
        // Create existing entity by processing an event first, then process an update
        // Create a modified request with different initial data
        EventHeader initialHeader = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanCreated")
                .setCreatedDate("2024-01-14T10:30:00Z")
                .setSavedDate("2024-01-14T10:30:00Z")
                .setEventType("LoanCreated")
                .build();
        
        Map<String, String> initialAttributes = new HashMap<>();
        initialAttributes.put("balance", "25000.00");
        initialAttributes.put("status", "active");
        
        EntityUpdate initialEntity = EntityUpdate.newBuilder()
                .setEntityType("Loan")
                .setEntityId("loan-12345")
                .putAllUpdatedAttributes(initialAttributes)
                .build();
        
        EventBody initialBody = EventBody.newBuilder()
                .addEntities(initialEntity)
                .build();
        
        EventRequest initialEvent = EventRequest.newBuilder()
                .setEventHeader(initialHeader)
                .setEventBody(initialBody)
                .build();
        
        TestStreamObserver<EventResponse> initialObserver = new TestStreamObserver<>();
        eventService.processEvent(initialEvent, initialObserver);
        EventResponse initialResponse = initialObserver.getResponse(); // Wait for initial creation
        assertThat(initialResponse.getSuccess()).isTrue(); // Verify initial creation succeeded
        
        CarEntity createdEntity = carEntityRepository.findByEntityTypeAndId("Loan", "loan-12345").block();
        assertThat(createdEntity).isNotNull(); // Verify entity was created
        OffsetDateTime initialUpdatedAt = createdEntity.getUpdatedAt();

        // Create update event
        EventRequest request = createValidEventRequest();
        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isTrue();

        // Verify entity was updated
        StepVerifier.create(carEntityRepository.findByEntityTypeAndId("Loan", "loan-12345"))
                .assertNext(entity -> {
                    assertThat(entity.getData()).contains("24439.75");
                    assertThat(entity.getData()).contains("2024-01-15T10:30:00Z");
                    assertThat(entity.getUpdatedAt()).isAfter(initialUpdatedAt);
                })
                .verifyComplete();
    }

    @Test
    void healthCheck_ShouldReturnHealthy() {
        // Given
        HealthRequest request = HealthRequest.newBuilder()
                .setService("producer-api-grpc")
                .build();
        TestStreamObserver<HealthResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.healthCheck(request, responseObserver);

        // Then
        HealthResponse response = responseObserver.getResponse();
        assertThat(response.getHealthy()).isTrue();
        assertThat(response.getMessage()).isEqualTo("Producer gRPC API is healthy");
    }

    @Test
    void processEvent_WithMultipleEntities_ShouldProcessAllEntities() {
        // Given
        Map<String, String> loanAttributes = new HashMap<>();
        loanAttributes.put("balance", "24439.75");
        loanAttributes.put("lastPaidDate", "2024-01-15T10:30:00Z");

        EntityUpdate loanEntity = EntityUpdate.newBuilder()
                .setEntityType("Loan")
                .setEntityId("loan-12345")
                .putAllUpdatedAttributes(loanAttributes)
                .build();

        Map<String, String> paymentAttributes = new HashMap<>();
        paymentAttributes.put("paymentAmount", "560.25");
        paymentAttributes.put("paymentDate", "2024-01-15T10:30:00Z");
        paymentAttributes.put("paymentMethod", "ACH");

        EntityUpdate paymentEntity = EntityUpdate.newBuilder()
                .setEntityType("LoanPayment")
                .setEntityId("payment-12345")
                .putAllUpdatedAttributes(paymentAttributes)
                .build();

        EventBody body = EventBody.newBuilder()
                .addEntities(loanEntity)
                .addEntities(paymentEntity)
                .build();

        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanPaymentSubmitted")
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:05Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();

        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isTrue();
        assertThat(response.getMessage()).isEqualTo("Event processed successfully");

        // Verify both entities were created
        StepVerifier.create(carEntityRepository.findByEntityTypeAndId("Loan", "loan-12345"))
                .assertNext(entity -> {
                    assertThat(entity.getId()).isEqualTo("loan-12345");
                    assertThat(entity.getEntityType()).isEqualTo("Loan");
                })
                .verifyComplete();

        StepVerifier.create(carEntityRepository.findByEntityTypeAndId("LoanPayment", "payment-12345"))
                .assertNext(entity -> {
                    assertThat(entity.getId()).isEqualTo("payment-12345");
                    assertThat(entity.getEntityType()).isEqualTo("LoanPayment");
                })
                .verifyComplete();
    }

    @Test
    void processEvent_WithEmptyEntitiesList_ShouldReturnError() {
        // Given
        EventBody body = EventBody.newBuilder()
                .build(); // Empty entities list

        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanPaymentSubmitted")
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:05Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();

        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getMessage()).contains("Invalid event");
    }

    @Test
    void processEvent_WithEmptyEventName_ShouldReturnError() {
        // Given
        Map<String, String> attributes = new HashMap<>();
        attributes.put("balance", "24439.75");

        EntityUpdate entityUpdate = EntityUpdate.newBuilder()
                .setEntityType("Loan")
                .setEntityId("loan-12345")
                .putAllUpdatedAttributes(attributes)
                .build();

        EventBody body = EventBody.newBuilder()
                .addEntities(entityUpdate)
                .build();

        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("") // Empty event name
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:05Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();

        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getMessage()).contains("Invalid event");
    }

    @Test
    void processEvent_WithEmptyEntityType_ShouldReturnError() {
        // Given
        Map<String, String> attributes = new HashMap<>();
        attributes.put("balance", "24439.75");

        EntityUpdate entityUpdate = EntityUpdate.newBuilder()
                .setEntityType("") // Empty entity type
                .setEntityId("loan-12345")
                .putAllUpdatedAttributes(attributes)
                .build();

        EventBody body = EventBody.newBuilder()
                .addEntities(entityUpdate)
                .build();

        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanPaymentSubmitted")
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:05Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();

        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getMessage()).contains("entityType cannot be empty");
    }

    @Test
    void processEvent_WithEmptyEntityId_ShouldReturnError() {
        // Given
        Map<String, String> attributes = new HashMap<>();
        attributes.put("balance", "24439.75");

        EntityUpdate entityUpdate = EntityUpdate.newBuilder()
                .setEntityType("Loan")
                .setEntityId("") // Empty entity ID
                .putAllUpdatedAttributes(attributes)
                .build();

        EventBody body = EventBody.newBuilder()
                .addEntities(entityUpdate)
                .build();

        EventHeader header = EventHeader.newBuilder()
                .setUuid("550e8400-e29b-41d4-a716-446655440000")
                .setEventName("LoanPaymentSubmitted")
                .setCreatedDate("2024-01-15T10:30:00Z")
                .setSavedDate("2024-01-15T10:30:05Z")
                .setEventType("LoanPaymentSubmitted")
                .build();

        EventRequest request = EventRequest.newBuilder()
                .setEventHeader(header)
                .setEventBody(body)
                .build();

        TestStreamObserver<EventResponse> responseObserver = new TestStreamObserver<>();

        // When
        eventService.processEvent(request, responseObserver);

        // Then
        EventResponse response = responseObserver.getResponse();
        assertThat(response.getSuccess()).isFalse();
        assertThat(response.getMessage()).contains("entityId cannot be empty");
    }

    private EventRequest createValidEventRequest() {
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
                .setEntityId("loan-12345")
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
