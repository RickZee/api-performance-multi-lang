package com.example.streamprocessor.service;

import com.example.streamprocessor.config.FilterConfig;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * HTTP client for fetching filters from Metadata Service API.
 * Handles retries, timeouts, and error scenarios.
 */
@Service
@Slf4j
public class MetadataServiceClient {
    
    private final WebClient webClient;
    private final ObjectMapper objectMapper;
    private final String baseUrl;
    private final Duration timeout;
    private final int maxRetries;
    
    public MetadataServiceClient(
            @Value("${metadata.service.url:http://localhost:8080}") String baseUrl,
            @Value("${metadata.service.timeout-seconds:5}") int timeoutSeconds,
            @Value("${metadata.service.max-retries:3}") int maxRetries,
            ObjectMapper objectMapper) {
        this.baseUrl = baseUrl;
        this.timeout = Duration.ofSeconds(timeoutSeconds);
        this.maxRetries = maxRetries;
        this.objectMapper = objectMapper;
        
        this.webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .defaultHeader("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                .build();
    }
    
    /**
     * Fetch active filters for a specific schema version from Metadata Service.
     * 
     * @param schemaVersion Schema version (e.g., "v1", "v2")
     * @return List of active filter configurations
     */
    public List<FilterConfig> fetchActiveFilters(String schemaVersion) {
        try {
            String responseBody = webClient.get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/api/v1/filters/active")
                            .queryParam("version", schemaVersion)
                            .build())
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, response -> {
                        log.error("Error fetching active filters: HTTP {}", response.statusCode());
                        return Mono.error(new RuntimeException("Failed to fetch filters: HTTP " + response.statusCode()));
                    })
                    .bodyToMono(String.class)
                    .timeout(timeout)
                    .retryWhen(Retry.fixedDelay(maxRetries, Duration.ofSeconds(1))
                            .filter(throwable -> throwable instanceof WebClientResponseException 
                                    && ((WebClientResponseException) throwable).getStatusCode().is5xxServerError())
                            .doBeforeRetry(retrySignal -> 
                                    log.warn("Retrying filter fetch (attempt {}/{}): {}", 
                                            retrySignal.totalRetries() + 1, maxRetries, retrySignal.failure().getMessage())))
                    .block();
            
            if (responseBody == null || responseBody.trim().isEmpty()) {
                log.warn("Empty response from Metadata Service for schema version: {}", schemaVersion);
                return Collections.emptyList();
            }
            
            // Parse JSON response - Metadata Service returns List<Filter> which we convert to FilterConfig
            // First parse as generic list of maps, then convert to FilterConfig
            List<Map<String, Object>> filterMaps = objectMapper.readValue(
                    responseBody, 
                    new TypeReference<List<Map<String, Object>>>() {});
            
            // Convert to FilterConfig objects
            List<FilterConfig> filters = filterMaps.stream()
                    .map(this::convertToFilterConfig)
                    .filter(java.util.Objects::nonNull)
                    .collect(java.util.stream.Collectors.toList());
            
            log.info("Fetched {} active filters from Metadata Service for schema version: {}", 
                    filters.size(), schemaVersion);
            
            return filters;
        } catch (WebClientResponseException e) {
            if (e.getStatusCode().value() == 404) {
                log.warn("No active filters found for schema version: {}", schemaVersion);
                return Collections.emptyList();
            }
            log.error("Error fetching active filters from Metadata Service: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to fetch filters from Metadata Service", e);
        } catch (Exception e) {
            log.error("Unexpected error fetching active filters: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to fetch filters from Metadata Service", e);
        }
    }
    
    /**
     * Check if Metadata Service is available.
     * 
     * @return true if service is available, false otherwise
     */
    public boolean isAvailable() {
        try {
            webClient.get()
                    .uri("/api/v1/health")
                    .retrieve()
                    .bodyToMono(String.class)
                    .timeout(Duration.ofSeconds(2))
                    .block();
            return true;
        } catch (Exception e) {
            log.debug("Metadata Service health check failed: {}", e.getMessage());
            return false;
        }
    }
    
    /**
     * Convert a map (from JSON) to FilterConfig.
     */
    private FilterConfig convertToFilterConfig(Map<String, Object> map) {
        try {
            FilterConfig config = new FilterConfig();
            config.setId((String) map.get("id"));
            config.setName((String) map.get("name"));
            config.setDescription((String) map.get("description"));
            config.setOutputTopic((String) map.get("outputTopic"));
            config.setConditionLogic((String) map.get("conditionLogic"));
            config.setEnabled((Boolean) map.get("enabled"));
            config.setStatus((String) map.get("status"));
            
            // Handle version - can be Integer or int
            Object versionObj = map.get("version");
            if (versionObj != null) {
                if (versionObj instanceof Integer) {
                    config.setVersion((Integer) versionObj);
                } else if (versionObj instanceof Number) {
                    config.setVersion(((Number) versionObj).intValue());
                }
            }
            
            // Convert conditions
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> conditionsList = (List<Map<String, Object>>) map.get("conditions");
            if (conditionsList != null) {
                List<com.example.streamprocessor.config.FilterCondition> conditions = conditionsList.stream()
                        .map(this::convertToFilterCondition)
                        .filter(java.util.Objects::nonNull)
                        .collect(java.util.stream.Collectors.toList());
                config.setConditions(conditions);
            }
            
            return config;
        } catch (Exception e) {
            log.error("Error converting map to FilterConfig: {}", e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * Convert a map to FilterCondition.
     */
    private com.example.streamprocessor.config.FilterCondition convertToFilterCondition(Map<String, Object> map) {
        try {
            com.example.streamprocessor.config.FilterCondition condition = 
                    new com.example.streamprocessor.config.FilterCondition();
            condition.setField((String) map.get("field"));
            condition.setOperator((String) map.get("operator"));
            
            // Convert value to String
            Object valueObj = map.get("value");
            if (valueObj != null) {
                condition.setValue(String.valueOf(valueObj));
            }
            
            condition.setValueType((String) map.get("valueType"));
            
            @SuppressWarnings("unchecked")
            List<Object> values = (List<Object>) map.get("values");
            if (values != null) {
                condition.setValues(values.stream()
                        .map(String::valueOf)
                        .collect(java.util.stream.Collectors.toList()));
            }
            
            // Convert min/max to String
            Object minObj = map.get("min");
            if (minObj != null) {
                condition.setMin(String.valueOf(minObj));
            }
            
            Object maxObj = map.get("max");
            if (maxObj != null) {
                condition.setMax(String.valueOf(maxObj));
            }
            
            return condition;
        } catch (Exception e) {
            log.error("Error converting map to FilterCondition: {}", e.getMessage(), e);
            return null;
        }
    }
}

