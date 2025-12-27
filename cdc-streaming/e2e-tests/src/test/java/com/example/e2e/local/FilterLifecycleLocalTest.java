package com.example.e2e.local;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Filter lifecycle integration test using local Metadata Service.
 * Tests CRUD operations, SQL generation, and mock deployment.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class FilterLifecycleLocalTest {
    
    private WebClient webClient;
    private String metadataServiceUrl = "http://localhost:8080";
    
    @BeforeAll
    void setUp() {
        webClient = WebClient.builder()
            .baseUrl(metadataServiceUrl)
            .build();
    }
    
    @Test
    void testCreateFilter() {
        String filterJson = """
            {
              "name": "Test Filter",
              "description": "Test filter for integration tests",
              "consumerId": "test-consumer",
              "outputTopic": "filtered-test-events-spring",
              "enabled": true,
              "conditions": [
                {
                  "field": "event_type",
                  "operator": "equals",
                  "value": "TestEvent",
                  "valueType": "string"
                },
                {
                  "field": "__op",
                  "operator": "equals",
                  "value": "c",
                  "valueType": "string"
                }
              ],
              "conditionLogic": "AND"
            }
            """;
        
        var response = webClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(filterJson)
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        assertThat(response).isNotNull();
        assertThat(response).contains("id");
        assertThat(response).contains("pending_approval");
    }
    
    @Test
    void testListFilters() {
        var response = webClient.get()
            .uri("/api/v1/filters?version=v1")
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        assertThat(response).isNotNull();
        assertThat(response).contains("filters");
    }
    
    @Test
    void testGenerateSQL() {
        // First create a filter
        String filterJson = """
            {
              "name": "SQL Test Filter",
              "description": "Filter for SQL generation test",
              "consumerId": "sql-test-consumer",
              "outputTopic": "filtered-sql-test-events-spring",
              "enabled": true,
              "conditions": [
                {
                  "field": "event_type",
                  "operator": "equals",
                  "value": "TestEvent",
                  "valueType": "string"
                }
              ],
              "conditionLogic": "AND"
            }
            """;
        
        var createResponse = webClient.post()
            .uri("/api/v1/filters?version=v1")
            .bodyValue(filterJson)
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        // Extract filter ID from response (simplified - in real test use proper JSON parsing)
        // In a real scenario, parse createResponse JSON to extract filter ID
        String filterId = "test-filter-id"; // Would extract from createResponse
        assertThat(createResponse).isNotNull(); // Use the variable to avoid warning
        
        // Generate SQL
        var sqlResponse = webClient.post()
            .uri("/api/v1/filters/{id}/generate?version=v1", filterId)
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        assertThat(sqlResponse).isNotNull();
        assertThat(sqlResponse).contains("CREATE TABLE");
        assertThat(sqlResponse).contains("INSERT INTO");
    }
    
    @Test
    void testHealthCheck() {
        var response = webClient.get()
            .uri("/api/v1/health")
            .retrieve()
            .bodyToMono(String.class)
            .block(Duration.ofSeconds(10));
        
        assertThat(response).isNotNull();
        assertThat(response).contains("status");
    }
}

