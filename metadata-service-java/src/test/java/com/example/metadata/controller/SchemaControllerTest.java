package com.example.metadata.controller;

import com.example.metadata.model.SchemaResponse;
import com.example.metadata.model.VersionsResponse;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@WebFluxTest(SchemaController.class)
class SchemaControllerTest {
    
    @Autowired
    private WebTestClient webTestClient;
    
    @MockBean
    private SchemaCacheService schemaCacheService;
    
    @MockBean
    private GitSyncService gitSyncService;
    
    @Test
    void testGetVersions() throws IOException {
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.getVersions("/tmp/cache")).thenReturn(List.of("v1", "v2"));
        
        webTestClient.get()
            .uri("/api/v1/schemas/versions")
            .exchange()
            .expectStatus().isOk()
            .expectBody(VersionsResponse.class)
            .value(response -> {
                assertEquals(2, response.getVersions().size());
                assertTrue(response.getVersions().contains("v1"));
                assertTrue(response.getVersions().contains("v2"));
                assertEquals("latest", response.getDefaultVersion());
            });
    }
    
    @Test
    void testGetVersions_Error() throws IOException {
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.getVersions("/tmp/cache")).thenThrow(new IOException("Failed"));
        
        webTestClient.get()
            .uri("/api/v1/schemas/versions")
            .exchange()
            .expectStatus().is5xxServerError();
    }
    
    @Test
    void testGetSchema_EventType() throws IOException {
        Map<String, Object> eventSchema = new HashMap<>();
        eventSchema.put("type", "object");
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        cachedSchema.setEventSchema(eventSchema);
        cachedSchema.setEntitySchemas(new HashMap<>());
        
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        
        webTestClient.get()
            .uri("/api/v1/schemas/v1?type=event")
            .exchange()
            .expectStatus().isOk()
            .expectBody(SchemaResponse.class)
            .value(response -> {
                assertEquals("v1", response.getVersion());
                assertNotNull(response.getSchema());
                assertEquals("object", response.getSchema().get("type"));
            });
    }
    
    @Test
    void testGetSchema_EntityType() throws IOException {
        Map<String, Object> carSchema = new HashMap<>();
        carSchema.put("type", "object");
        carSchema.put("title", "Car");
        
        Map<String, Map<String, Object>> entitySchemas = new HashMap<>();
        entitySchemas.put("car", carSchema);
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        cachedSchema.setEventSchema(new HashMap<>());
        cachedSchema.setEntitySchemas(entitySchemas);
        
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        
        webTestClient.get()
            .uri("/api/v1/schemas/v1?type=car")
            .exchange()
            .expectStatus().isOk()
            .expectBody(SchemaResponse.class)
            .value(response -> {
                assertEquals("v1", response.getVersion());
                assertNotNull(response.getSchema());
                assertEquals("Car", response.getSchema().get("title"));
            });
    }
    
    @Test
    void testGetSchema_DefaultType() throws IOException {
        Map<String, Object> eventSchema = new HashMap<>();
        eventSchema.put("type", "object");
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        cachedSchema.setEventSchema(eventSchema);
        cachedSchema.setEntitySchemas(new HashMap<>());
        
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        
        webTestClient.get()
            .uri("/api/v1/schemas/v1") // No type parameter - defaults to "event"
            .exchange()
            .expectStatus().isOk()
            .expectBody(SchemaResponse.class)
            .value(response -> {
                assertEquals("v1", response.getVersion());
                assertNotNull(response.getSchema());
            });
    }
    
    @Test
    void testGetSchema_NotFound() throws IOException {
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.loadVersion(eq("v999"), anyString()))
            .thenThrow(new IOException("Version not found"));
        
        webTestClient.get()
            .uri("/api/v1/schemas/v999")
            .exchange()
            .expectStatus().isNotFound();
    }
    
    @Test
    void testGetSchema_NonExistentEntityType() throws IOException {
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        cachedSchema.setEventSchema(new HashMap<>());
        cachedSchema.setEntitySchemas(new HashMap<>());
        
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/cache");
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        
        webTestClient.get()
            .uri("/api/v1/schemas/v1?type=nonexistent")
            .exchange()
            .expectStatus().isOk()
            .expectBody(SchemaResponse.class)
            .value(response -> {
                assertEquals("v1", response.getVersion());
                assertTrue(response.getSchema().isEmpty()); // Empty map for non-existent entity
            });
    }
}
