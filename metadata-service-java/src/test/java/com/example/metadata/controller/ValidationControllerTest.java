package com.example.metadata.controller;

import com.example.metadata.config.AppConfig;
import com.example.metadata.model.ValidationRequest;
import com.example.metadata.model.ValidationResponse;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
import com.example.metadata.service.SchemaValidationService;
import com.example.metadata.testutil.TestEventGenerator;
import com.example.metadata.testutil.TestRepoSetup;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.io.IOException;
import java.nio.file.Files;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;

@WebFluxTest(controllers = ValidationController.class)
@TestPropertySource(properties = {
    "spring.main.allow-bean-definition-overriding=true"
})
class ValidationControllerTest {
    
    @Autowired
    private WebTestClient webTestClient;
    
    @MockBean
    private SchemaValidationService validationService;
    
    @MockBean
    private SchemaCacheService schemaCacheService;
    
    @MockBean
    private GitSyncService gitSyncService;
    
    @MockBean
    private AppConfig appConfig;
    
    @BeforeEach
    void setUp() {
        // Setup default mocks
        AppConfig.ValidationConfig validationConfig = new AppConfig.ValidationConfig();
        validationConfig.setDefaultVersion("v1");
        validationConfig.setAcceptedVersions(java.util.List.of("v1"));
        validationConfig.setStrictMode(true);
        when(appConfig.getValidation()).thenReturn(validationConfig);
        
        when(gitSyncService.getLocalDir()).thenReturn("/tmp/test-cache");
    }
    
    @Test
    void testValidateEvent_Valid() throws IOException {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        ValidationRequest request = new ValidationRequest();
        request.setEvent(event);
        request.setVersion("v1");
        
        SchemaValidationService.ValidationResult validationResult = new SchemaValidationService.ValidationResult();
        validationResult.setValid(true);
        validationResult.setVersion("v1");
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        when(validationService.validateEvent(any(), any(), any(), anyString()))
            .thenReturn(validationResult);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(ValidationResponse.class)
            .value(response -> {
                assertTrue(response.isValid());
                assertEquals("v1", response.getVersion());
            });
    }
    
    @Test
    void testValidateEvent_Invalid_StrictMode() throws IOException {
        Map<String, Object> event = TestEventGenerator.invalidEventMissingRequired();
        ValidationRequest request = new ValidationRequest();
        request.setEvent(event);
        request.setVersion("v1");
        
        SchemaValidationService.ValidationResult validationResult = new SchemaValidationService.ValidationResult();
        validationResult.setValid(false);
        validationResult.setVersion("v1");
        validationResult.getErrors().add(new SchemaValidationService.ValidationError());
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        when(validationService.validateEvent(any(), any(), any(), anyString()))
            .thenReturn(validationResult);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isEqualTo(422) // Unprocessable Entity in strict mode
            .expectBody(ValidationResponse.class)
            .value(response -> {
                assertFalse(response.isValid());
            });
    }
    
    @Test
    void testValidateEvent_Invalid_LenientMode() throws IOException {
        AppConfig.ValidationConfig validationConfig = new AppConfig.ValidationConfig();
        validationConfig.setDefaultVersion("v1");
        validationConfig.setAcceptedVersions(java.util.List.of("v1"));
        validationConfig.setStrictMode(false); // Lenient mode
        when(appConfig.getValidation()).thenReturn(validationConfig);
        
        Map<String, Object> event = TestEventGenerator.invalidEventMissingRequired();
        ValidationRequest request = new ValidationRequest();
        request.setEvent(event);
        request.setVersion("v1");
        
        SchemaValidationService.ValidationResult validationResult = new SchemaValidationService.ValidationResult();
        validationResult.setValid(false);
        validationResult.setVersion("v1");
        validationResult.getErrors().add(new SchemaValidationService.ValidationError());
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        when(validationService.validateEvent(any(), any(), any(), anyString()))
            .thenReturn(validationResult);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk() // 200 OK in lenient mode
            .expectBody(ValidationResponse.class)
            .value(response -> {
                assertFalse(response.isValid());
            });
    }
    
    @Test
    void testValidateEvent_DefaultVersion() throws IOException {
        Map<String, Object> event = TestEventGenerator.validCarCreatedEvent();
        ValidationRequest request = new ValidationRequest();
        request.setEvent(event);
        // No version specified
        
        SchemaValidationService.ValidationResult validationResult = new SchemaValidationService.ValidationResult();
        validationResult.setValid(true);
        validationResult.setVersion("v1");
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        when(validationService.validateEvent(any(), any(), any(), anyString()))
            .thenReturn(validationResult);
        
        webTestClient.post()
            .uri("/api/v1/validate")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk();
    }
    
    @Test
    void testValidateBulkEvents() throws IOException {
        // Set lenient mode for this test
        AppConfig.ValidationConfig validationConfig = new AppConfig.ValidationConfig();
        validationConfig.setDefaultVersion("v1");
        validationConfig.setAcceptedVersions(java.util.List.of("v1"));
        validationConfig.setStrictMode(false); // Lenient mode
        when(appConfig.getValidation()).thenReturn(validationConfig);
        
        Map<String, Object> event1 = TestEventGenerator.validCarCreatedEvent();
        Map<String, Object> event2 = TestEventGenerator.invalidEventMissingRequired();
        
        com.example.metadata.model.ValidateBulkEventsRequest request = 
            new com.example.metadata.model.ValidateBulkEventsRequest();
        request.setEvents(java.util.List.of(event1, event2));
        request.setVersion("v1");
        
        SchemaValidationService.ValidationResult result1 = new SchemaValidationService.ValidationResult();
        result1.setValid(true);
        result1.setVersion("v1");
        
        SchemaValidationService.ValidationResult result2 = new SchemaValidationService.ValidationResult();
        result2.setValid(false);
        result2.setVersion("v1");
        
        SchemaCacheService.CachedSchema cachedSchema = new SchemaCacheService.CachedSchema();
        when(schemaCacheService.loadVersion(eq("v1"), anyString())).thenReturn(cachedSchema);
        when(validationService.validateEvent(any(), any(), any(), anyString()))
            .thenReturn(result1, result2);
        
        webTestClient.post()
            .uri("/api/v1/validate/bulk")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(request)
            .exchange()
            .expectStatus().isOk()
            .expectBody(com.example.metadata.model.ValidateBulkEventsResponse.class)
            .value(response -> {
                assertEquals(2, response.getSummary().getTotal());
                assertEquals(1, response.getSummary().getValid());
                assertEquals(1, response.getSummary().getInvalid());
                assertEquals(2, response.getResults().size());
            });
    }
}
