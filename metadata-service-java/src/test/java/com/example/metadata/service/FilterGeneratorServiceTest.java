package com.example.metadata.service;

import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import com.example.metadata.model.GenerateSQLResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class FilterGeneratorServiceTest {
    
    private FilterGeneratorService generatorService;
    
    @BeforeEach
    void setUp() {
        generatorService = new FilterGeneratorService();
    }
    
    @Test
    void testGenerateSQL_ValidFilter() {
        Filter filter = Filter.builder()
            .id("test-filter-001")
            .name("Service Events for Dealer 001")
            .outputTopic("filtered-service-events-dealer-001")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarServiceDone")
                    .valueType("string")
                    .build(),
                FilterCondition.builder()
                    .field("header_data.dealerId")
                    .operator("equals")
                    .value("DEALER-001")
                    .valueType("string")
                    .build()
            ))
            .conditionLogic("AND")
            .build();
        
        GenerateSQLResponse response = generatorService.generateSQL(filter);
        
        assertTrue(response.isValid());
        assertNotNull(response.getSql());
        assertEquals(2, response.getStatements().size());
        assertTrue(response.getSql().contains("CREATE TABLE"));
        assertTrue(response.getSql().contains("INSERT INTO"));
        assertTrue(response.getSql().contains("filtered-service-events-dealer-001"));
        assertTrue(response.getSql().contains("DEALER-001"));
        assertTrue(response.getSql().contains("JSON_VALUE"));
    }
    
    @Test
    void testGenerateSQL_DisabledFilter() {
        Filter filter = Filter.builder()
            .id("test-filter-002")
            .name("Disabled Filter")
            .outputTopic("test-topic")
            .enabled(false)
            .conditions(List.of())
            .build();
        
        GenerateSQLResponse response = generatorService.generateSQL(filter);
        
        assertFalse(response.isValid());
        assertNotNull(response.getValidationErrors());
        assertTrue(response.getValidationErrors().contains("filter is disabled"));
    }
    
    @Test
    void testGenerateSQL_WithInOperator() {
        Filter filter = Filter.builder()
            .id("test-filter-003")
            .name("Filter with IN operator")
            .outputTopic("test-topic")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("in")
                    .values(List.of("CarCreated", "CarServiceDone"))
                    .valueType("string")
                    .build()
            ))
            .conditionLogic("AND")
            .build();
        
        GenerateSQLResponse response = generatorService.generateSQL(filter);
        
        assertTrue(response.isValid());
        assertTrue(response.getSql().contains("IN ("));
        assertTrue(response.getSql().contains("CarCreated"));
        assertTrue(response.getSql().contains("CarServiceDone"));
    }
    
    @Test
    void testGenerateSQL_WithORLogic() {
        Filter filter = Filter.builder()
            .id("test-filter-004")
            .name("Filter with OR logic")
            .outputTopic("test-topic")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarCreated")
                    .valueType("string")
                    .build(),
                FilterCondition.builder()
                    .field("event_type")
                    .operator("equals")
                    .value("CarServiceDone")
                    .valueType("string")
                    .build()
            ))
            .conditionLogic("OR")
            .build();
        
        GenerateSQLResponse response = generatorService.generateSQL(filter);
        
        assertTrue(response.isValid());
        assertTrue(response.getSql().contains("OR"));
    }
    
    @Test
    void testGenerateSQL_WithBetweenOperator() {
        Filter filter = Filter.builder()
            .id("test-filter-005")
            .name("Filter with BETWEEN operator")
            .outputTopic("test-topic")
            .enabled(true)
            .conditions(List.of(
                FilterCondition.builder()
                    .field("year")
                    .operator("between")
                    .min(2020)
                    .max(2024)
                    .valueType("integer")
                    .build()
            ))
            .conditionLogic("AND")
            .build();
        
        GenerateSQLResponse response = generatorService.generateSQL(filter);
        
        assertTrue(response.isValid());
        assertTrue(response.getSql().contains("BETWEEN"));
    }
}
