package com.example.grpc;

import com.example.constants.ApiConstants;
import com.example.dto.Event;
import com.example.repository.DuplicateEventError;
import com.example.service.EventConverter;
import com.example.service.EventProcessingService;
import io.grpc.Status;
import io.grpc.stub.StreamObserver;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.devh.boot.grpc.server.service.GrpcService;

import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicReference;

@GrpcService
@RequiredArgsConstructor
@Slf4j
public class EventServiceImpl extends EventServiceGrpc.EventServiceImplBase {
    
    private final EventProcessingService eventProcessingService;
    private final EventConverter eventConverter;

    @Override
    public void processEvent(EventRequest request, StreamObserver<EventResponse> responseObserver) {
        log.info("{} Received gRPC event: {}", ApiConstants.API_NAME, 
                request.hasEventHeader() ? request.getEventHeader().getEventName() : "unknown");
        
        try {
            // Validate request
            if (!request.hasEventHeader()) {
                sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid event: missing eventHeader");
                return;
            }
            
            if (request.getEventHeader().getEventName().isEmpty()) {
                sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid event: eventName cannot be empty");
                return;
            }
            
            if (request.getEntitiesList().isEmpty()) {
                sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid event: entities list cannot be empty");
                return;
            }
            
            // Validate each entity
            for (com.example.grpc.Entity entity : request.getEntitiesList()) {
                if (!entity.hasEntityHeader()) {
                    sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid entity: missing entityHeader");
                    return;
                }
                if (entity.getEntityHeader().getEntityType().isEmpty()) {
                    sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid entity: entityType cannot be empty");
                    return;
                }
                if (entity.getEntityHeader().getEntityId().isEmpty()) {
                    sendErrorResponse(responseObserver, Status.INVALID_ARGUMENT, "Invalid entity: entityId cannot be empty");
                    return;
                }
            }
            
            // Convert protobuf to internal model
            Event event = eventConverter.convertFromProto(request);
            
            // Process event with synchronization using CountDownLatch
            // This avoids blocking the reactive context which causes deadlocks with R2DBC transactions
            // The reactive chain will execute on the R2DBC thread, and we wait for it to complete
            final CountDownLatch latch = new CountDownLatch(1);
            final AtomicReference<Throwable> errorRef = new AtomicReference<>();
            final AtomicReference<Boolean> responseSent = new AtomicReference<>(false);
            
            eventProcessingService.processEvent(event)
                    .timeout(Duration.ofSeconds(55)) // Timeout before client timeout
                    .subscribe(
                            v -> {
                                // Success - send response
                                synchronized (responseSent) {
                                    if (!responseSent.get()) {
                                        EventResponse successResponse = EventResponse.newBuilder()
                                                .setSuccess(true)
                                                .setMessage("Event processed successfully")
                                                .build();
                                        responseObserver.onNext(successResponse);
                                        responseObserver.onCompleted();
                                        responseSent.set(true);
                                    }
                                }
                                latch.countDown();
                            },
                            error -> {
                                // Error occurred - store it and signal completion
                                errorRef.set(error);
                                latch.countDown();
                            }
                    );
            
            // Wait for completion with timeout (55 seconds to be under client timeout of 60s)
            try {
                if (!latch.await(55, TimeUnit.SECONDS)) {
                    log.error("{} Event processing timed out after 55 seconds", ApiConstants.API_NAME);
                    synchronized (responseSent) {
                        if (!responseSent.get()) {
                            sendErrorResponse(responseObserver, Status.DEADLINE_EXCEEDED, 
                                    "Event processing timed out after 55 seconds");
                            responseSent.set(true);
                        }
                    }
                    return;
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.error("{} Event processing interrupted", ApiConstants.API_NAME, e);
                synchronized (responseSent) {
                    if (!responseSent.get()) {
                        sendErrorResponse(responseObserver, Status.INTERNAL, 
                                "Event processing was interrupted");
                        responseSent.set(true);
                    }
                }
                return;
            }
            
            // Check for errors - only send error response if success response wasn't already sent
            Throwable error = errorRef.get();
            if (error != null) {
                synchronized (responseSent) {
                    if (!responseSent.get()) {
                        if (error instanceof DuplicateEventError) {
                            DuplicateEventError dupErr = (DuplicateEventError) error;
                            log.warn("{} Duplicate event ID: {}", ApiConstants.API_NAME, dupErr.getEventId());
                            sendErrorResponse(responseObserver, Status.ALREADY_EXISTS, 
                                    "Event with ID '" + dupErr.getEventId() + "' already exists");
                        } else if (error instanceof TimeoutException || 
                                  (error.getCause() != null && error.getCause() instanceof TimeoutException) ||
                                  (error.getMessage() != null && error.getMessage().contains("timed out"))) {
                            log.error("{} Event processing timed out", ApiConstants.API_NAME, error);
                            sendErrorResponse(responseObserver, Status.DEADLINE_EXCEEDED, 
                                    "Event processing timed out after 55 seconds");
                        } else {
                            log.error("{} Error processing gRPC event", ApiConstants.API_NAME, error);
                            sendErrorResponse(responseObserver, Status.INTERNAL, 
                                    "Error processing event: " + error.getMessage());
                        }
                        responseSent.set(true);
                    }
                }
            }
            
        } catch (Exception e) {
            log.error("{} Error processing gRPC event", ApiConstants.API_NAME, e);
            sendErrorResponse(responseObserver, Status.INTERNAL, "Error processing event: " + e.getMessage());
        }
    }

    private void sendErrorResponse(StreamObserver<EventResponse> responseObserver, Status status, String message) {
        responseObserver.onError(status.withDescription(message).asException());
    }

    @Override
    public void healthCheck(HealthRequest request, StreamObserver<HealthResponse> responseObserver) {
        log.info("{} Health check requested for service: {}", ApiConstants.API_NAME, request.getService());
        
        HealthResponse response = HealthResponse.newBuilder()
                .setHealthy(true)
                .setMessage("Producer gRPC API is healthy")
                .build();
        
        responseObserver.onNext(response);
        responseObserver.onCompleted();
    }
}
