package com.example.metadata.controller;

import com.example.metadata.model.CompatibilityRequest;
import com.example.metadata.model.CompatibilityResponse;
import com.example.metadata.model.SchemaResponse;
import com.example.metadata.model.VersionsResponse;
import com.example.metadata.service.CompatibilityService;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/schemas")
@RequiredArgsConstructor
public class SchemaController {
    private final SchemaCacheService schemaCacheService;
    private final GitSyncService gitSyncService;
    private final CompatibilityService compatibilityService;

    @GetMapping("/versions")
    public ResponseEntity<VersionsResponse> getVersions() {
        try {
            List<String> versions = schemaCacheService.getVersions(gitSyncService.getLocalDir());
            return ResponseEntity.ok(VersionsResponse.builder()
                .versions(versions)
                .defaultVersion("latest")
                .build());
        } catch (IOException e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/{version}")
    public ResponseEntity<SchemaResponse> getSchema(
            @PathVariable String version,
            @RequestParam(required = false, defaultValue = "event") String type
    ) {
        try {
            SchemaCacheService.CachedSchema cached = schemaCacheService.loadVersion(version, gitSyncService.getLocalDir());
            
            Map<String, Object> schema;
            if ("event".equals(type)) {
                schema = cached.getEventSchema();
            } else {
                schema = cached.getEntitySchemas().getOrDefault(type, new HashMap<>());
            }
            
            return ResponseEntity.ok(SchemaResponse.builder()
                .version(version)
                .schema(schema)
                .build());
        } catch (IOException e) {
            return ResponseEntity.notFound().build();
        }
    }
    
    @PostMapping("/compatibility")
    public ResponseEntity<CompatibilityResponse> checkCompatibility(
            @Valid @RequestBody CompatibilityRequest request
    ) {
        try {
            String oldVersion = request.getOldVersion();
            String newVersion = request.getNewVersion();
            String type = request.getType() != null && !request.getType().isEmpty() 
                ? request.getType() 
                : "event";
            
            String localDir = gitSyncService.getLocalDir();
            
            // Load old schema
            SchemaCacheService.CachedSchema oldCached = schemaCacheService.loadVersion(oldVersion, localDir);
            Map<String, Object> oldSchema;
            if ("event".equals(type)) {
                oldSchema = oldCached.getEventSchema();
            } else {
                oldSchema = oldCached.getEntitySchemas().getOrDefault(type, new HashMap<>());
                if (oldSchema.isEmpty()) {
                    return ResponseEntity.notFound().build();
                }
            }
            
            // Load new schema
            SchemaCacheService.CachedSchema newCached = schemaCacheService.loadVersion(newVersion, localDir);
            Map<String, Object> newSchema;
            if ("event".equals(type)) {
                newSchema = newCached.getEventSchema();
            } else {
                newSchema = newCached.getEntitySchemas().getOrDefault(type, new HashMap<>());
                if (newSchema.isEmpty()) {
                    return ResponseEntity.notFound().build();
                }
            }
            
            // Check compatibility
            CompatibilityService.CompatibilityResult result = compatibilityService.checkCompatibility(oldSchema, newSchema);
            
            return ResponseEntity.ok(CompatibilityResponse.builder()
                .compatible(result.isCompatible())
                .reason(result.getReason())
                .breakingChanges(result.getBreakingChanges())
                .nonBreakingChanges(result.getNonBreakingChanges())
                .oldVersion(oldVersion)
                .newVersion(newVersion)
                .build());
        } catch (IOException e) {
            return ResponseEntity.notFound().build();
        }
    }
}
