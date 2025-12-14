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

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@Slf4j
public class FilterStorageService {
    private final ObjectMapper objectMapper;
    private final String baseDir;
    
    private final ReentrantReadWriteLock lock = new ReentrantReadWriteLock();

    public FilterStorageService(GitSyncService gitSyncService) {
        this.baseDir = gitSyncService.getLocalDir();
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }

    public Filter create(String version, CreateFilterRequest request) throws IOException {
        lock.writeLock().lock();
        try {
            String filterId = generateFilterId(request.getName());
            Path filtersDir = getFiltersDir(version);
            Path filterPath = filtersDir.resolve(filterId + ".json");
            
            // Check if filter already exists
            if (Files.exists(filterPath)) {
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
            return loadFilter(version, filterId);
        } finally {
            lock.readLock().unlock();
        }
    }

    public List<Filter> list(String version) throws IOException {
        lock.readLock().lock();
        try {
            Path filtersDir = getFiltersDir(version);
            
            if (!Files.exists(filtersDir)) {
                return new ArrayList<>();
            }
            
            try (Stream<Path> paths = Files.list(filtersDir)) {
                return paths
                    .filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(".json"))
                    .map(p -> {
                        try {
                            return objectMapper.readValue(p.toFile(), Filter.class);
                        } catch (IOException e) {
                            log.warn("Failed to read filter file: {}", p, e);
                            return null;
                        }
                    })
                    .filter(Objects::nonNull)
                    .collect(Collectors.toList());
            }
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
            Path filtersDir = getFiltersDir(version);
            Path filterPath = filtersDir.resolve(filterId + ".json");
            
            if (!Files.exists(filterPath)) {
                throw new FilterNotFoundException(filterId, version);
            }
            
            Files.delete(filterPath);
            
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
        Path filtersDir = getFiltersDir(version);
        Path filterPath = filtersDir.resolve(filterId + ".json");
        
        if (!Files.exists(filterPath)) {
            throw new FilterNotFoundException(filterId, version);
        }
        
        try {
            return objectMapper.readValue(filterPath.toFile(), Filter.class);
        } catch (IOException e) {
            throw new IOException("Failed to read filter: " + filterId, e);
        }
    }

    private void save(String version, Filter filter) throws IOException {
        Path filtersDir = getFiltersDir(version);
        Files.createDirectories(filtersDir);
        
        Path filterPath = filtersDir.resolve(filter.getId() + ".json");
        objectMapper.writerWithDefaultPrettyPrinter()
            .writeValue(filterPath.toFile(), filter);
    }

    private Path getFiltersDir(String version) {
        // Check if baseDir contains a "schemas" subdirectory (git repo structure)
        Path basePath = Paths.get(baseDir);
        Path schemasSubDir = basePath.resolve("schemas");
        if (Files.exists(schemasSubDir)) {
            return schemasSubDir.resolve(version).resolve("filters");
        }
        return basePath.resolve("schemas").resolve(version).resolve("filters");
    }

    private String generateFilterId(String name) {
        // Convert name to kebab-case and add timestamp for uniqueness
        String kebabCase = name.toLowerCase()
            .replaceAll("[^a-z0-9]+", "-")
            .replaceAll("^-|-$", "");
        return kebabCase + "-" + System.currentTimeMillis();
    }
}
