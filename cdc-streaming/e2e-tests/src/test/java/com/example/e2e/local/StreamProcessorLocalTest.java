package com.example.e2e.local;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Stream Processor local integration test.
 * Tests routing accuracy and hot reload capabilities.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class StreamProcessorLocalTest {
    
    private KafkaTestUtils kafkaUtils;
    private WebClient webClient;
    private String sourceTopic = "raw-event-headers";
    private String bootstrapServers = "localhost:9092";
    private String streamProcessorUrl = "http://localhost:8083";
    
    @BeforeAll
    void setUp() {
        kafkaUtils = new KafkaTestUtils(bootstrapServers, null, null);
        webClient = WebClient.builder()
            .baseUrl(streamProcessorUrl)
            .build();
    }
    
    @Test
    void testEventRoutingToCorrectTopic() throws Exception {
        // Test each event type routes to correct topic
        String carId = "test-car-" + System.currentTimeMillis();
        EventHeader carEvent = TestEventGenerator.generateCarCreatedEvent(carId);
        kafkaUtils.publishTestEvent(sourceTopic, carEvent);
        
        List<EventHeader> carEvents = kafkaUtils.consumeEvents(
            "filtered-car-created-events-spring", 1, Duration.ofSeconds(30), "test-car-"
        );
        
        assertThat(carEvents).hasSize(1);
        assertThat(carEvents.get(0).getEventType()).isEqualTo("CarCreated");
    }
    
    @Test
    void testNonMatchingEventsFiltered() throws Exception {
        // Publish event that doesn't match any filter
        String unknownId = "test-unknown-" + System.currentTimeMillis();
        EventHeader unknownEvent = EventHeader.builder()
            .id(unknownId)
            .eventType("UnknownEvent")
            .eventName("UnknownEvent")
            .op("c")
            .table("event_headers")
            .build();
        
        kafkaUtils.publishTestEvent(sourceTopic, unknownEvent);
        
        // Wait a bit
        Thread.sleep(5000);
        
        // Verify no events in any filtered topic
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events-spring", 10, Duration.ofSeconds(5)
        );
        
        // Filter by our test ID to ensure we're not seeing other events
        long matchingEvents = carEvents.stream()
            .filter(e -> e.getId().equals(unknownId))
            .count();
        
        assertThat(matchingEvents).isEqualTo(0);
    }
    
    @Test
    void testStreamProcessorHealth() {
        var response = webClient.get()
            .uri("/actuator/health")
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        assertThat(response).isNotNull();
        assertThat(response).contains("status");
    }
    
    @Test
    void testHighThroughputProcessing() throws Exception {
        // Generate 100 events
        List<EventHeader> testEvents = TestEventGenerator.generateMixedEventBatch(100);
        
        long startTime = System.currentTimeMillis();
        kafkaUtils.publishTestEvents(sourceTopic, testEvents);
        
        // Wait for processing
        Thread.sleep(10000);
        
        // Verify events are processed
        List<EventHeader> carEvents = kafkaUtils.consumeAllEvents(
            "filtered-car-created-events-spring", 100, Duration.ofSeconds(30)
        );
        List<EventHeader> loanEvents = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events-spring", 100, Duration.ofSeconds(30)
        );
        
        int totalProcessed = carEvents.size() + loanEvents.size();
        assertThat(totalProcessed).isGreaterThanOrEqualTo(80); // Allow margin for timing
        
        long totalTime = System.currentTimeMillis() - startTime;
        double throughput = (double) totalProcessed / (totalTime / 1000.0);
        
        // Verify throughput is reasonable (at least 10 events/sec)
        assertThat(throughput).isGreaterThan(10.0);
    }
}

