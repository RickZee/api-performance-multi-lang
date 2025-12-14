package com.example.metadata.service;

import com.example.metadata.model.Filter;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Service
@Slf4j
public class SchemaCacheService {
    private final ObjectMapper objectMapper;
    private final Map<String, CachedSchema> cache = new ConcurrentHashMap<>();
    private static final long CACHE_TTL_SECONDS = 3600; // 1 hour

    public SchemaCacheService() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }

    @Data
    public static class CachedSchema {
        private String version;
        private Map<String, Object> schema = new HashMap<>();
        private Map<String, Object> eventSchema = new HashMap<>();
        private Map<String, Map<String, Object>> entitySchemas = new HashMap<>();
        private List<Filter> filters = new ArrayList<>();
        private Instant loadedAt = Instant.now();
    }

    public CachedSchema loadVersion(String version, String schemasDir) throws IOException {
        // Check cache first
        CachedSchema cached = cache.get(version);
        if (cached != null) {
            long age = Instant.now().getEpochSecond() - cached.getLoadedAt().getEpochSecond();
            if (age < CACHE_TTL_SECONDS) {
                return cached;
            }
        }

        // Load from disk
        CachedSchema schema = loadFromDisk(version, schemasDir);
        cache.put(version, schema);
        return schema;
    }

    private CachedSchema loadFromDisk(String version, String schemasDir) throws IOException {
        // Check if schemasDir contains a "schemas" subdirectory (git repo structure)
        Path schemasPath = Paths.get(schemasDir);
        Path schemasSubDir = schemasPath.resolve("schemas");
        if (Files.exists(schemasSubDir)) {
            schemasDir = schemasSubDir.toString();
        }

        Path versionDir = Paths.get(schemasDir, version);
        if (!Files.exists(versionDir)) {
            throw new IOException("Version directory not found: " + versionDir);
        }

        CachedSchema cached = new CachedSchema();
        cached.setVersion(version);
        cached.setLoadedAt(Instant.now());

        // Load event schema
        Path eventDir = versionDir.resolve("event");
        Path eventSchemaPath = eventDir.resolve("event.json");
        if (Files.exists(eventSchemaPath)) {
            try {
                Map<String, Object> eventSchema = objectMapper.readValue(
                    eventSchemaPath.toFile(), 
                    Map.class
                );
                cached.setEventSchema(eventSchema);
                
                // Extract filters from event schema
                if (eventSchema.containsKey("filters")) {
                    Object filtersObj = eventSchema.get("filters");
                    if (filtersObj instanceof List) {
                        List<Map<String, Object>> filtersList = (List<Map<String, Object>>) filtersObj;
                        List<Filter> filters = filtersList.stream()
                            .map(filterMap -> {
                                try {
                                    return objectMapper.convertValue(filterMap, Filter.class);
                                } catch (Exception e) {
                                    log.warn("Failed to parse filter: {}", filterMap, e);
                                    return null;
                                }
                            })
                            .filter(Objects::nonNull)
                            .collect(Collectors.toList());
                        cached.setFilters(filters);
                        log.info("Loaded {} filters from event schema", filters.size());
                    }
                }
            } catch (IOException e) {
                log.warn("Failed to load event schema: {}", eventSchemaPath, e);
            }
        }

        // Load event schemas (like event-header.json) into entitySchemas for reference resolution
        if (Files.exists(eventDir)) {
            try {
                Files.list(eventDir)
                    .filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(".json"))
                    .forEach(eventSchemaFile -> {
                        try {
                            String fileName = eventSchemaFile.getFileName().toString();
                            String schemaName = fileName.substring(0, fileName.length() - 5); // Remove .json
                            
                            Map<String, Object> schema = objectMapper.readValue(
                                eventSchemaFile.toFile(),
                                Map.class
                            );
                            // Store with both name and filename for reference resolution
                            cached.getEntitySchemas().put(schemaName, schema);
                            cached.getEntitySchemas().put(fileName, schema);
                        } catch (IOException e) {
                            log.warn("Failed to load event schema file: {}", eventSchemaFile, e);
                        }
                    });
            } catch (IOException e) {
                log.warn("Failed to list event directory: {}", eventDir, e);
            }
        }

        // Load entity schemas
        Path entityDir = versionDir.resolve("entity");
        if (Files.exists(entityDir)) {
            try {
                Files.list(entityDir)
                    .filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(".json"))
                    .forEach(entityPath -> {
                        try {
                            String fileName = entityPath.getFileName().toString();
                            String entityName = fileName.substring(0, fileName.length() - 5); // Remove .json
                            
                            Map<String, Object> entitySchema = objectMapper.readValue(
                                entityPath.toFile(),
                                Map.class
                            );
                            // Store with both name and filename for reference resolution
                            cached.getEntitySchemas().put(entityName, entitySchema);
                            cached.getEntitySchemas().put(fileName, entitySchema);
                        } catch (IOException e) {
                            log.warn("Failed to load entity schema: {}", entityPath, e);
                        }
                    });
            } catch (IOException e) {
                log.warn("Failed to list entity directory: {}", entityDir, e);
            }
        }

        log.info("Loaded schema version: version={}, entityCount={}, filterCount={}", 
            version, cached.getEntitySchemas().size(), cached.getFilters().size());

        return cached;
    }

    public List<String> getVersions(String schemasDir) throws IOException {
        // Check if schemasDir contains a "schemas" subdirectory (git repo structure)
        Path schemasPath = Paths.get(schemasDir);
        Path schemasSubDir = schemasPath.resolve("schemas");
        if (Files.exists(schemasSubDir)) {
            schemasDir = schemasSubDir.toString();
        }

        Path schemasPath2 = Paths.get(schemasDir);
        if (!Files.exists(schemasPath2)) {
            throw new IOException("Schemas directory not found: " + schemasDir);
        }

        List<String> versions = new ArrayList<>();
        try {
            Files.list(schemasPath2)
                .filter(Files::isDirectory)
                .filter(p -> !p.getFileName().toString().equals(".git"))
                .forEach(p -> versions.add(p.getFileName().toString()));
        } catch (IOException e) {
            throw new IOException("Failed to read schemas directory: " + schemasDir, e);
        }

        Collections.sort(versions);
        return versions;
    }

    public void invalidate(String version) {
        cache.remove(version);
    }

    public void invalidateAll() {
        cache.clear();
    }
}
