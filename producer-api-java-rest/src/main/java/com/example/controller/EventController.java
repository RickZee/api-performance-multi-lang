package com.example.controller;

import com.example.dto.Event;
import com.example.service.EventProcessingService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import jakarta.validation.Valid;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
@RequestMapping("/api/v1/events")
@RequiredArgsConstructor
@Slf4j
public class EventController {

    private final EventProcessingService eventProcessingService;

    @PostMapping
    public Mono<ResponseEntity<String>> processEvent(@Valid @RequestBody(required = false) Event event) {
        // Handle null event body explicitly
        if (event == null) {
            return Mono.just(ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                    .body("Invalid request: Event body is required"));
        }
        
        log.info("Received event: {}", event.getEventHeader() != null ? 
                event.getEventHeader().getEventName() : "null or invalid");
        
        return eventProcessingService.processEvent(event)
                .then(Mono.just(ResponseEntity.ok("Event processed successfully")))
                .doOnError(error -> log.warn("Error in reactive chain: {} - {}", error.getClass().getName(), error.getMessage()))
                .onErrorResume(IllegalArgumentException.class, ex -> {
                    log.warn("Caught IllegalArgumentException: {}", ex.getMessage());
                    return Mono.just(ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                            .body("Invalid event: " + ex.getMessage()));
                })
                .onErrorResume(RuntimeException.class, ex -> {
                    // Check if it's an IllegalArgumentException wrapped in RuntimeException
                    Throwable cause = ex.getCause();
                    if (cause instanceof IllegalArgumentException) {
                        log.warn("Caught wrapped IllegalArgumentException: {}", cause.getMessage());
                        return Mono.just(ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                                .body("Invalid event: " + cause.getMessage()));
                    }
                    log.error("Caught RuntimeException: {} - {}", ex.getClass().getName(), ex.getMessage(), ex);
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body("Error processing event: " + ex.getMessage()));
                })
                .onErrorResume(throwable -> {
                    log.error("Caught unexpected error: {} - {}", throwable.getClass().getName(), throwable.getMessage(), throwable);
                    return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body("Error processing event: " + throwable.getMessage()));
                });
    }

    @PostMapping("/bulk")
    public Mono<ResponseEntity<Map<String, Object>>> processBulkEvents(@RequestBody java.util.List<Event> events) {
        if (events == null || events.isEmpty()) {
            return Mono.just(ResponseEntity.badRequest().body(Map.of(
                "success", false,
                "message", "Invalid request: events list is null or empty",
                "processedCount", 0,
                "failedCount", 0
            )));
        }
        
        log.info("Received bulk request with {} events", events.size());
        
        AtomicInteger processedCount = new AtomicInteger(0);
        AtomicInteger failedCount = new AtomicInteger(0);
        long startTime = System.currentTimeMillis();
        String batchId = "batch-" + System.currentTimeMillis();
        
        return Flux.fromIterable(events)
                .flatMap(event -> {
                    // Validate event structure
                    if (event == null || event.getEventHeader() == null) {
                        failedCount.incrementAndGet();
                        log.warn("Skipping invalid event: null or missing header");
                        return Mono.just(false);
                    }
                    
                    // Process event reactively
                    return eventProcessingService.processEvent(event)
                            .then(Mono.fromCallable(() -> {
                                processedCount.incrementAndGet();
                                return true;
                            }))
                            .onErrorResume(error -> {
                                failedCount.incrementAndGet();
                                log.error("Error processing event in bulk: {}", error.getMessage(), error);
                                return Mono.just(false);
                            });
                })
                .then(Mono.fromCallable(() -> {
                    int processed = processedCount.get();
                    int failed = failedCount.get();
                    boolean success = failed == 0;
                    String message = success ? 
                        "All events processed successfully" : 
                        String.format("Processed %d events, %d failed", processed, failed);
                    long processingTimeMs = System.currentTimeMillis() - startTime;
                    
                    return ResponseEntity.ok(Map.of(
                        "success", success,
                        "message", message,
                        "processedCount", processed,
                        "failedCount", failed,
                        "batchId", batchId,
                        "processingTimeMs", processingTimeMs
                    ));
                }));
    }

    @GetMapping("/health")
    public Mono<ResponseEntity<String>> health() {
        return Mono.just(ResponseEntity.ok("Producer API is healthy"));
    }
}
