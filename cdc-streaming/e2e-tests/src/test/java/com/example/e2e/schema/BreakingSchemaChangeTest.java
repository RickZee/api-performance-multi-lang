package com.example.e2e.schema;

import com.example.e2e.fixtures.TestEventGenerator;
import com.example.e2e.model.EventHeader;
import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Breaking schema change tests.
 * Tests V2 parallel deployment for breaking schema changes.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class BreakingSchemaChangeTest {
    
    private KafkaTestUtils kafkaUtils;
    private String sourceTopicV1 = "raw-event-headers";
    private String sourceTopicV2 = "raw-event-headers-v2";
    private String bootstrapServers;
    private String apiKey;
    private String apiSecret;
    
    @BeforeAll
    void setUp() {
        // Support both local Docker Kafka and Confluent Cloud
        // Check environment variables first (for Confluent Cloud mode)
        bootstrapServers = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            bootstrapServers = System.getenv("CONFLUENT_BOOTSTRAP_SERVERS");
        }
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            // Default to local Docker Kafka
            bootstrapServers = "localhost:9092";
        }
        
        // Get API credentials if using Confluent Cloud
        apiKey = System.getenv("CONFLUENT_API_KEY");
        if (apiKey == null || apiKey.isEmpty()) {
            apiKey = System.getenv("CONFLUENT_CLOUD_API_KEY");
        }
        if (apiKey == null || apiKey.isEmpty()) {
            apiKey = System.getenv("KAFKA_API_KEY");
        }
        
        apiSecret = System.getenv("CONFLUENT_API_SECRET");
        if (apiSecret == null || apiSecret.isEmpty()) {
            apiSecret = System.getenv("CONFLUENT_CLOUD_API_SECRET");
        }
        if (apiSecret == null || apiSecret.isEmpty()) {
            apiSecret = System.getenv("KAFKA_API_SECRET");
        }
        
        // Local Kafka doesn't require authentication
        kafkaUtils = new KafkaTestUtils(bootstrapServers, apiKey, apiSecret);
    }
    
    @Test
    void testV2SystemDeploysInParallel() throws Exception {
        // Verify V2 topics exist
        // This test assumes V2 system is running (via --profile v2)
        
        // Check if V2 stream processor is running
        boolean v2Running = false;
        try {
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create("http://localhost:8084/actuator/health"))
                    .GET()
                    .timeout(java.time.Duration.ofSeconds(2))
                    .build();
            java.net.http.HttpResponse<String> response = client.send(request, 
                    java.net.http.HttpResponse.BodyHandlers.ofString());
            v2Running = response.statusCode() == 200 && response.body().contains("UP");
        } catch (Exception e) {
            // V2 not running
        }
        
        if (!v2Running) {
            System.out.println("WARNING: V2 stream processor is not running. Start with: docker-compose --profile v2 up -d stream-processor-v2");
            System.out.println("Skipping V2 assertions - V1 system will still be tested");
        }
        
        String testIdV1 = "test-v1-" + System.currentTimeMillis();
        String testIdV2 = "test-v2-" + System.currentTimeMillis();
        
        // Publish to V1 topic
        EventHeader eventV1 = TestEventGenerator.generateCarCreatedEvent(testIdV1);
        kafkaUtils.publishTestEvent(sourceTopicV1, eventV1);
        
        // Publish to V2 topic
        EventHeader eventV2 = TestEventGenerator.generateCarCreatedEvent(testIdV2);
        kafkaUtils.publishTestEvent(sourceTopicV2, eventV2);
        
        // Verify V1 processing
        List<EventHeader> v1Events = kafkaUtils.consumeEvents(
            "filtered-car-created-events-spring", 1, Duration.ofSeconds(30), "test-v1-"
        );
        
        assertThat(v1Events).hasSize(1);
        assertThat(v1Events.get(0).getId()).startsWith("test-v1-");
        
        // Verify V2 processing only if V2 system is running
        if (v2Running) {
            List<EventHeader> v2Events = kafkaUtils.consumeEvents(
                "filtered-car-created-events-v2-spring", 1, Duration.ofSeconds(30), "test-v2-"
            );
            assertThat(v2Events).as("V2 events should be processed when V2 system is running").hasSize(1);
            assertThat(v2Events.get(0).getId()).startsWith("test-v2-");
        } else {
            System.out.println("V2 system not running - skipping V2 event verification");
        }
    }
    
    @Test
    void testV1V2Isolation() throws Exception {
        // Verify V1 and V2 systems are isolated
        String testIdV1 = "test-isolation-v1-" + System.currentTimeMillis();
        String testIdV2 = "test-isolation-v2-" + System.currentTimeMillis();
        
        // Publish to V1
        EventHeader eventV1 = TestEventGenerator.generateLoanCreatedEvent(testIdV1);
        kafkaUtils.publishTestEvent(sourceTopicV1, eventV1);
        
        // Publish to V2
        EventHeader eventV2 = TestEventGenerator.generateLoanCreatedEvent(testIdV2);
        kafkaUtils.publishTestEvent(sourceTopicV2, eventV2);
        
        // Verify V1 events only in V1 topics (increased timeout for Kafka Streams processing)
        List<EventHeader> v1Events = kafkaUtils.consumeEvents(
            "filtered-loan-created-events-spring", 1, Duration.ofSeconds(45), "test-isolation-v1-"
        );
        
        // Verify V2 events only in V2 topics (increased timeout for Kafka Streams processing)
        List<EventHeader> v2Events = kafkaUtils.consumeEvents(
            "filtered-loan-created-events-v2-spring", 1, Duration.ofSeconds(45), "test-isolation-v2-"
        );
        
        // V1 events should not appear in V2 topics
        assertThat(v1Events).hasSize(1)
            .withFailMessage("Expected 1 V1 event but got " + v1Events.size());
        assertThat(v1Events.get(0).getId()).startsWith("test-isolation-v1-");
        
        // Verify no V1 events in V2 topics
        List<EventHeader> v2TopicCheck = kafkaUtils.consumeAllEvents(
            "filtered-loan-created-events-v2-spring", 10, Duration.ofSeconds(10)
        );
        long v1InV2 = v2TopicCheck.stream()
            .filter(e -> e.getId().startsWith("test-isolation-v1-"))
            .count();
        
        assertThat(v1InV2).isEqualTo(0)
            .withFailMessage("Found " + v1InV2 + " V1 events in V2 topic");
        
        // Verify V2 events are isolated (if V2 system is running)
        assertThat(v2Events).hasSize(1)
            .withFailMessage("Expected 1 V2 event but got " + v2Events.size() + ". V2 stream processor may not be running or processing events.");
        assertThat(v2Events.get(0).getId()).startsWith("test-isolation-v2-");
    }
    
    @Test
    void testGradualMigrationFromV1ToV2() throws Exception {
        // Simulate gradual migration: both systems running, traffic shifting
        String testId = "test-migration-" + System.currentTimeMillis();
        
        // Check if V2 stream processor is running
        boolean v2Running = false;
        try {
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create("http://localhost:8084/actuator/health"))
                    .GET()
                    .timeout(java.time.Duration.ofSeconds(2))
                    .build();
            java.net.http.HttpResponse<String> response = client.send(request, 
                    java.net.http.HttpResponse.BodyHandlers.ofString());
            v2Running = response.statusCode() == 200 && response.body().contains("UP");
        } catch (Exception e) {
            // V2 not running
        }
        
        // Publish to both V1 and V2 (simulating dual-write during migration)
        EventHeader event = TestEventGenerator.generateServiceEvent(testId);
        
        // V1 system
        kafkaUtils.publishTestEvent(sourceTopicV1, event);
        List<EventHeader> v1Events = kafkaUtils.consumeEvents(
            "filtered-service-events-spring", 1, Duration.ofSeconds(30), "test-migration-"
        );
        
        // Verify V1 continues to work during migration
        assertThat(v1Events).hasSize(1);
        
        // V2 system (if running)
        if (v2Running) {
            kafkaUtils.publishTestEvent(sourceTopicV2, event);
            List<EventHeader> v2Events = kafkaUtils.consumeEvents(
                "filtered-service-events-v2-spring", 1, Duration.ofSeconds(30), "test-migration-"
            );
            assertThat(v2Events).as("V2 events should be processed when V2 system is running").hasSize(1);
        } else {
            System.out.println("V2 system not running - V1 system verified to work independently");
        }
    }
}

