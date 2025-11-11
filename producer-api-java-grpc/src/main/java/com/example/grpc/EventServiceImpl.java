package com.example.grpc;

import com.example.service.EventProcessingService;
import io.grpc.stub.StreamObserver;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.devh.boot.grpc.server.service.GrpcService;
import reactor.core.publisher.Mono;

import java.util.Map;

@GrpcService
@RequiredArgsConstructor
@Slf4j
public class EventServiceImpl extends EventServiceGrpc.EventServiceImplBase {

    private final EventProcessingService eventProcessingService;

    @Override
    public void processEvent(EventRequest request, StreamObserver<EventResponse> responseObserver) {
        log.info("Received gRPC event: {}", request.getEventHeader().getEventName());
        
        try {
            // Validate request - proto3 returns default instances, not null
            // Check if required fields are present and non-empty
            if (request.getEventHeader().getEventName().isEmpty() ||
                request.getEventBody().getEntitiesList().isEmpty()) {
                EventResponse errorResponse = EventResponse.newBuilder()
                        .setSuccess(false)
                        .setMessage("Invalid event: missing eventName or entities")
                        .build();
                responseObserver.onNext(errorResponse);
                responseObserver.onCompleted();
                return;
            }

            // Validate each entity update
            for (EntityUpdate entityUpdate : request.getEventBody().getEntitiesList()) {
                if (entityUpdate.getEntityType().isEmpty()) {
                    EventResponse errorResponse = EventResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Invalid event: entityType cannot be empty")
                            .build();
                    responseObserver.onNext(errorResponse);
                    responseObserver.onCompleted();
                    return;
                }
                if (entityUpdate.getEntityId().isEmpty()) {
                    EventResponse errorResponse = EventResponse.newBuilder()
                            .setSuccess(false)
                            .setMessage("Invalid event: entityId cannot be empty")
                            .build();
                    responseObserver.onNext(errorResponse);
                    responseObserver.onCompleted();
                    return;
                }
            }

            // Process each entity update
            for (EntityUpdate entityUpdate : request.getEventBody().getEntitiesList()) {
                eventProcessingService.processEvent(
                        request.getEventHeader().getEventName(),
                        entityUpdate.getEntityType(),
                        entityUpdate.getEntityId(),
                        entityUpdate.getUpdatedAttributesMap()
                ).block(); // Block for simplicity in this implementation
            }

            EventResponse successResponse = EventResponse.newBuilder()
                    .setSuccess(true)
                    .setMessage("Event processed successfully")
                    .build();
            
            responseObserver.onNext(successResponse);
            responseObserver.onCompleted();
            
        } catch (Exception e) {
            log.error("Error processing gRPC event", e);
            
            EventResponse errorResponse = EventResponse.newBuilder()
                    .setSuccess(false)
                    .setMessage("Error processing event: " + e.getMessage())
                    .build();
            
            responseObserver.onNext(errorResponse);
            responseObserver.onCompleted();
        }
    }

    @Override
    public void healthCheck(HealthRequest request, StreamObserver<HealthResponse> responseObserver) {
        log.info("Health check requested for service: {}", request.getService());
        
        HealthResponse response = HealthResponse.newBuilder()
                .setHealthy(true)
                .setMessage("Producer gRPC API is healthy")
                .build();
        
        responseObserver.onNext(response);
        responseObserver.onCompleted();
    }
}
