package com.example.e2e.schema;

import com.example.e2e.utils.KafkaTestUtils;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;

import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Diagnostic tests to verify V2 system setup and configuration.
 * These tests help identify why V2 tests might be failing.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class V2SystemDiagnosticsTest {
    
    private KafkaTestUtils kafkaUtils;
    private String bootstrapServers;
    private String apiKey;
    private String apiSecret;
    
    @BeforeAll
    void setUp() {
        bootstrapServers = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            bootstrapServers = System.getenv("CONFLUENT_BOOTSTRAP_SERVERS");
        }
        if (bootstrapServers == null || bootstrapServers.isEmpty()) {
            bootstrapServers = "localhost:9092";
        }
        
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
        
        kafkaUtils = new KafkaTestUtils(bootstrapServers, apiKey, apiSecret);
    }
    
    @Test
    void testV2TopicsExist() {
        // Verify V2 topics exist by attempting to publish/consume
        // This is a simpler check than listing all topics
        try {
            String testId = "test-topic-check-" + System.currentTimeMillis();
            com.example.e2e.model.EventHeader event = com.example.e2e.fixtures.TestEventGenerator.generateCarCreatedEvent(testId);
            kafkaUtils.publishTestEvent("raw-event-headers-v2", event);
            System.out.println("✓ Successfully published to raw-event-headers-v2");
        } catch (Exception e) {
            System.out.println("✗ Failed to publish to raw-event-headers-v2: " + e.getMessage());
            throw new AssertionError("V2 topic raw-event-headers-v2 is not accessible", e);
        }
    }
    
    @Test
    void testV2StreamProcessorHealth() {
        // Check if V2 stream processor is running and healthy
        try {
            String healthUrl = "http://localhost:8084/actuator/health";
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(healthUrl))
                    .GET()
                    .build();
            java.net.http.HttpResponse<String> response = client.send(request, 
                    java.net.http.HttpResponse.BodyHandlers.ofString());
            
            assertThat(response.statusCode()).isEqualTo(200);
            assertThat(response.body()).contains("UP");
        } catch (Exception e) {
            // V2 processor might not be running - this is diagnostic info
            System.out.println("V2 Stream Processor health check failed: " + e.getMessage());
            System.out.println("This indicates V2 system may not be running. Start with: docker-compose --profile v2 up -d stream-processor-v2");
        }
    }
    
    @Test
    void testMetadataServiceV2Filters() {
        // Check if Metadata Service has V2 filters
        try {
            String filtersUrl = "http://localhost:8080/api/v1/filters/active?version=v2";
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(filtersUrl))
                    .GET()
                    .build();
            java.net.http.HttpResponse<String> response = client.send(request, 
                    java.net.http.HttpResponse.BodyHandlers.ofString());
            
            assertThat(response.statusCode()).isEqualTo(200);
            String body = response.body();
            assertThat(body).isNotNull();
            
            // Parse JSON to check if filters exist
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            java.util.List<?> filters = mapper.readValue(body, java.util.List.class);
            
            System.out.println("V2 Filters found: " + filters.size());
            if (filters.isEmpty()) {
                System.out.println("WARNING: No V2 filters found in Metadata Service!");
                System.out.println("V2 filters need to be created via API or seeded from filters-v2.json");
            } else {
                System.out.println("V2 Filters: " + mapper.writerWithDefaultPrettyPrinter().writeValueAsString(filters));
            }
        } catch (Exception e) {
            System.out.println("Failed to check V2 filters in Metadata Service: " + e.getMessage());
        }
    }
    
    @Test
    void testV2EventPublishing() {
        // Test if we can publish to V2 topic
        String testId = "test-v2-diagnostics-" + System.currentTimeMillis();
        try {
            com.example.e2e.model.EventHeader event = com.example.e2e.fixtures.TestEventGenerator.generateCarCreatedEvent(testId);
            kafkaUtils.publishTestEvent("raw-event-headers-v2", event);
            System.out.println("Successfully published event to raw-event-headers-v2");
            
            // Try to consume from V2 filtered topic
            List<com.example.e2e.model.EventHeader> events = kafkaUtils.consumeEvents(
                "filtered-car-created-events-v2-spring", 1, Duration.ofSeconds(10), testId
            );
            
            if (events.isEmpty()) {
                System.out.println("WARNING: Event published but not consumed from V2 filtered topic");
                System.out.println("Possible causes:");
                System.out.println("  1. V2 stream processor not running");
                System.out.println("  2. V2 stream processor not configured with Metadata Service");
                System.out.println("  3. V2 filters not loaded in Metadata Service");
                System.out.println("  4. V2 stream processor not listening to raw-event-headers-v2");
            } else {
                System.out.println("SUCCESS: Event was processed by V2 system");
            }
        } catch (Exception e) {
            System.out.println("Failed to test V2 event publishing: " + e.getMessage());
            e.printStackTrace();
        }
    }
}

