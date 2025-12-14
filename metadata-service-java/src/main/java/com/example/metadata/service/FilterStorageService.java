package com.example.metadata.service;

import com.example.metadata.exception.FilterNotFoundException;
import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import com.example.metadata.model.CreateFilterRequest;
import com.example.metadata.model.UpdateFilterRequest;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.locks.ReentrantReadWriteLock;

@Service
@Slf4j
public class FilterStorageService {
    private final ObjectMapper objectMapper;
    private final String baseDir;
    private final SchemaCacheService schemaCacheService;
    
    private final ReentrantReadWriteLock lock = new ReentrantReadWriteLock();

    public FilterStorageService(GitSyncService gitSyncService, SchemaCacheService schemaCacheService) {
        this.baseDir = gitSyncService.getLocalDir();
        this.schemaCacheService = schemaCacheService;
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }

    public Filter create(String version, CreateFilterRequest request) throws IOException {
        lock.writeLock().lock();
        try {
            String filterId = generateFilterId(request.getName());
            
            // Check if filter already exists (without acquiring another lock)
            SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion(version, baseDir);
            boolean exists = schema.getFilters().stream()
                .anyMatch(f -> f.getId().equals(filterId));
            if (exists) {
                throw new IOException("Filter with ID " + filterId + " already exists");
            }
            
            Instant now = Instant.now();
            Filter filter = Filter.builder()
                .id(filterId)
                .name(request.getName())
                .description(request.getDescription())
                .consumerId(request.getConsumerId())
                .outputTopic(request.getOutputTopic())
                .conditions(request.getConditions())
                .enabled(request.isEnabled())
                .conditionLogic(request.getConditionLogic() != null ? request.getConditionLogic() : "AND")
                .status("pending_approval")
                .createdAt(now)
                .updatedAt(now)
                .version(1)
                .build();
            
            save(version, filter);
            
            log.info("Filter created: version={}, filterId={}, name={}", 
                version, filterId, filter.getName());
            
            return filter;
        } finally {
            lock.writeLock().unlock();
        }
    }

    public Filter get(String version, String filterId) throws IOException {
        lock.readLock().lock();
        try {
            SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion(version, baseDir);
            return schema.getFilters().stream()
                .filter(f -> f.getId().equals(filterId))
                .findFirst()
                .orElseThrow(() -> new FilterNotFoundException(filterId, version));
        } finally {
            lock.readLock().unlock();
        }
    }

    public List<Filter> list(String version) throws IOException {
        lock.readLock().lock();
        try {
            SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion(version, baseDir);
            return new ArrayList<>(schema.getFilters());
        } finally {
            lock.readLock().unlock();
        }
    }

    public Filter update(String version, String filterId, UpdateFilterRequest request) throws IOException {
        lock.writeLock().lock();
        try {
            Filter filter = loadFilter(version, filterId);
            
            // Update fields if provided
            if (request.getName() != null) {
                filter.setName(request.getName());
            }
            if (request.getDescription() != null) {
                filter.setDescription(request.getDescription());
            }
            if (request.getConsumerId() != null) {
                filter.setConsumerId(request.getConsumerId());
            }
            if (request.getOutputTopic() != null) {
                filter.setOutputTopic(request.getOutputTopic());
            }
            if (request.getConditions() != null && !request.getConditions().isEmpty()) {
                filter.setConditions(request.getConditions());
            }
            if (request.getEnabled() != null) {
                filter.setEnabled(request.getEnabled());
            }
            if (request.getConditionLogic() != null) {
                filter.setConditionLogic(request.getConditionLogic());
            }
            
            filter.setUpdatedAt(Instant.now());
            filter.setVersion(filter.getVersion() + 1);
            
            save(version, filter);
            
            log.info("Filter updated: version={}, filterId={}", version, filterId);
            
            return filter;
        } finally {
            lock.writeLock().unlock();
        }
    }

    public void delete(String version, String filterId) throws IOException {
        lock.writeLock().lock();
        try {
            Path eventJsonPath = getEventJsonPath(version);
            
            if (!Files.exists(eventJsonPath)) {
                throw new FilterNotFoundException(filterId, version);
            }
            
            // Read current event.json
            Map<String, Object> eventSchema = objectMapper.readValue(
                eventJsonPath.toFile(), 
                Map.class
            );
            
            // Get filters array
            List<Map<String, Object>> filters = (List<Map<String, Object>>) 
                eventSchema.getOrDefault("filters", new ArrayList<>());
            
            // Remove filter
            boolean removed = filters.removeIf(f -> filterId.equals(f.get("id")));
            if (!removed) {
                throw new FilterNotFoundException(filterId, version);
            }
            
            // Write back to event.json
            eventSchema.put("filters", filters);
            objectMapper.writerWithDefaultPrettyPrinter()
                .writeValue(eventJsonPath.toFile(), eventSchema);
            
            // Invalidate cache to force reload on next access
            schemaCacheService.invalidate(version);
            
            // Force a reload to ensure the cache has the updated state
            schemaCacheService.loadVersion(version, baseDir);
            
            log.info("Filter deleted: version={}, filterId={}", version, filterId);
        } finally {
            lock.writeLock().unlock();
        }
    }

    public Filter approve(String version, String filterId, String approvedBy) throws IOException {
        lock.writeLock().lock();
        try {
            Filter filter = loadFilter(version, filterId);
            
            if (!"pending_approval".equals(filter.getStatus())) {
                throw new IOException("Filter is not in pending_approval status");
            }
            
            filter.setStatus("approved");
            filter.setApprovedBy(approvedBy);
            filter.setApprovedAt(Instant.now());
            filter.setUpdatedAt(Instant.now());
            
            save(version, filter);
            
            log.info("Filter approved: version={}, filterId={}, approvedBy={}", 
                version, filterId, approvedBy);
            
            return filter;
        } finally {
            lock.writeLock().unlock();
        }
    }

    public Filter updateDeployment(String version, String filterId, String status, 
                                   List<String> flinkStatementIds, String error) throws IOException {
        lock.writeLock().lock();
        try {
            Filter filter = loadFilter(version, filterId);
            
            filter.setStatus(status);
            filter.setFlinkStatementIds(flinkStatementIds);
            if (error != null) {
                filter.setDeploymentError(error);
            }
            if ("deployed".equals(status)) {
                filter.setDeployedAt(Instant.now());
            }
            filter.setUpdatedAt(Instant.now());
            
            save(version, filter);
            
            return filter;
        } finally {
            lock.writeLock().unlock();
        }
    }

    private Filter loadFilter(String version, String filterId) throws IOException {
        SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion(version, baseDir);
        return schema.getFilters().stream()
            .filter(f -> f.getId().equals(filterId))
            .findFirst()
            .orElseThrow(() -> new FilterNotFoundException(filterId, version));
    }

    private void save(String version, Filter filter) throws IOException {
        Path eventJsonPath = getEventJsonPath(version);
        
        // Ensure directory exists
        Files.createDirectories(eventJsonPath.getParent());
        
        // Read current event.json or create new one
        Map<String, Object> eventSchema;
        if (Files.exists(eventJsonPath)) {
            eventSchema = objectMapper.readValue(eventJsonPath.toFile(), Map.class);
        } else {
            // Create minimal event schema structure if it doesn't exist
            eventSchema = new HashMap<>();
            eventSchema.put("$schema", "https://json-schema.org/draft/2020-12/schema");
            eventSchema.put("type", "object");
            eventSchema.put("properties", new HashMap<>());
            eventSchema.put("required", Arrays.asList("eventHeader", "entities"));
        }
        
        // Get or create filters array
        List<Map<String, Object>> filters = (List<Map<String, Object>>) 
            eventSchema.getOrDefault("filters", new ArrayList<>());
        
        // Convert filter to map
        Map<String, Object> filterMap = objectMapper.convertValue(filter, Map.class);
        
        // Update or add filter
        int index = findFilterIndex(filters, filter.getId());
        if (index >= 0) {
            filters.set(index, filterMap);
        } else {
            filters.add(filterMap);
        }
        
        // Write back to event.json
        eventSchema.put("filters", filters);
        objectMapper.writerWithDefaultPrettyPrinter()
            .writeValue(eventJsonPath.toFile(), eventSchema);
        
        // Invalidate cache to force reload on next access
        schemaCacheService.invalidate(version);
        
        // Force a reload to ensure the cache has the updated filter
        // This ensures that subsequent reads will see the new filter
        schemaCacheService.loadVersion(version, baseDir);
    }

    private Path getEventJsonPath(String version) {
        Path basePath = Paths.get(baseDir);
        Path schemasSubDir = basePath.resolve("schemas");
        if (Files.exists(schemasSubDir)) {
            return schemasSubDir.resolve(version).resolve("event").resolve("event.json");
        }
        return basePath.resolve("schemas").resolve(version).resolve("event").resolve("event.json");
    }

    private int findFilterIndex(List<Map<String, Object>> filters, String filterId) {
        for (int i = 0; i < filters.size(); i++) {
            if (filterId.equals(filters.get(i).get("id"))) {
                return i;
            }
        }
        return -1;
    }

    private String generateFilterId(String name) {
        // Convert name to kebab-case and add timestamp for uniqueness
        String kebabCase = name.toLowerCase()
            .replaceAll("[^a-z0-9]+", "-")
            .replaceAll("^-|-$", "");
        return kebabCase + "-" + System.currentTimeMillis();
    }
}
