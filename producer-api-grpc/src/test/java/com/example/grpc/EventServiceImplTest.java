package com.example.grpc;

import com.example.service.EventProcessingService;
import io.grpc.stub.StreamObserver;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EventServiceImplTest {

    @Mock
    private EventProcessingService eventProcessingService;

    @Mock
    private StreamObserver<EventResponse> eventResponseObserver;

    @Mock
    private StreamObserver<HealthResponse> healthResponseObserver;

    private EventServiceImpl eventService;

    @BeforeEach
    void setUp() {
        eventService = new EventServiceImpl(eventProcessingService);
    }

    @Test
    void processEvent_WithValidEvent_ShouldReturnSuccess() {
        // Given
        EventRequest request = createValidEventRequest();
        when(eventProcessingService.processEvent(anyString(), anyString(), anyString(), any(Map.class)))
                .thenReturn(Mono.empty());

        // When
        eventService.processEvent(request, eventResponseObserver);

        // Then
        verify(eventProcessingService).processEvent(
                eq("LoanPaymentSubmitted"),
                eq("Loan"),
                eq("loan-12345"),
                any(Map.class)
        );
        verify(eventResponseObserver).onNext(any(EventResponse.class));
        verify(eventResponseObserver).onCompleted();
    }

    @Test
    void processEvent_WithInvalidEvent_ShouldReturnError() {
        // Given
        EventRequest request = EventRequest.newBuilder()
                .setEventBody(EventBody.newBuilder().build())
                .build(); // Missing event header

        // When
        eventService.processEvent(request, eventResponseObserver);

        // Then
        verify(eventProcessingService, never()).processEvent(anyString(), anyString(), anyString(), any(Map.class));
        verify(eventResponseObserver).onNext(any(EventResponse.class));
        verify(eventResponseObserver).onCompleted();
    }

    @Test
    void processEvent_WithServiceError_ShouldReturnError() {
        // Given
        EventRequest request = createValidEventRequest();
        when(eventProcessingService.processEvent(anyString(), anyString(), anyString(), any(Map.class)))
                .thenReturn(Mono.error(new RuntimeException("Database error")));

        // When
        eventService.processEvent(request, eventResponseObserver);

        // Then
        verify(eventProcessingService).processEvent(
                eq("LoanPaymentSubmitted"),
                eq("Loan"),
                eq("loan-12345"),
                any(Map.class)
        );
        verify(eventResponseObserver).onNext(any(EventResponse.class));
        verify(eventResponseObserver).onCompleted();
    }

    @Test
    void healthCheck_ShouldReturnHealthy() {
        // Given
        HealthRequest request = HealthRequest.newBuilder()
                .setService("producer-api-grpc")
                .build();

        // When
        eventService.healthCheck(request, healthResponseObserver);

        // Then
        verify(healthResponseObserver).onNext(any(HealthResponse.class));
        verify(healthResponseObserver).onCompleted();
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
