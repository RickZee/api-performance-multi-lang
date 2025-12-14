package com.example.metadata.controller;

import com.example.metadata.model.SchemaResponse;
import com.example.metadata.model.VersionsResponse;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
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
}
