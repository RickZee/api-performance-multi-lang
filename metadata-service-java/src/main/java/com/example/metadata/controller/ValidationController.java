package com.example.metadata.controller;

import com.example.metadata.config.AppConfig;
import com.example.metadata.model.*;
import com.example.metadata.service.GitSyncService;
import com.example.metadata.service.SchemaCacheService;
import com.example.metadata.service.SchemaValidationService;
import lombok.RequiredArgsConstructor;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
public class ValidationController {
    private final SchemaValidationService validationService;
    private final SchemaCacheService schemaCacheService;
    private final GitSyncService gitSyncService;
    private final AppConfig config;

    @PostMapping("/validate")
    public ResponseEntity<ValidationResponse> validateEvent(@Valid @RequestBody ValidationRequest request) {
        try {
            String requestedVersion = request.getVersion();
            String version = determineVersion(requestedVersion);
            List<String> acceptedVersions = config.getValidation().getAcceptedVersions();
            if (acceptedVersions == null || acceptedVersions.isEmpty()) {
                acceptedVersions = List.of(version);
            }

            // If a specific version was requested and it's not in accepted versions, check if it exists
            if (requestedVersion != null && !requestedVersion.isEmpty() && 
                !"latest".equals(requestedVersion) && !acceptedVersions.contains(requestedVersion)) {
                // Try to load the requested version to see if it exists
                try {
                    String localDir = gitSyncService.getLocalDir();
                    schemaCacheService.loadVersion(requestedVersion, localDir);
                    // If it loads successfully, add it to accepted versions for this request
                    acceptedVersions = List.of(requestedVersion);
                } catch (IOException e) {
                    // Version doesn't exist - return 500
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
                }
            }

            SchemaValidationService.ValidationResult validationResult = null;
            String validatedVersion = version;

            for (String v : acceptedVersions) {
                if ("latest".equals(v)) {
                    v = version;
                }
                
                try {
                    String localDir = gitSyncService.getLocalDir();
                    SchemaCacheService.CachedSchema schema = schemaCacheService.loadVersion(v, localDir);
                    // For validateEvent, we need to pass the schemas directory path
                    // SchemaValidationService expects the base path where schemas/v1/event is located
                    String schemasBasePath = localDir;
                    Path schemasPath = Paths.get(localDir);
                    Path schemasSubDir = schemasPath.resolve("schemas");
                    if (Files.exists(schemasSubDir)) {
                        schemasBasePath = schemasSubDir.toString();
                    } else {
                        schemasBasePath = Paths.get(localDir, "schemas").toString();
                    }
                    SchemaValidationService.ValidationResult result = validationService.validateEvent(
                        request.getEvent(),
                        schema.getEventSchema(),
                        schema.getEntitySchemas(),
                        schemasBasePath
                    );
                    
                    if (result.isValid()) {
                        validationResult = result;
                        validatedVersion = v;
                        break;
                    }
                    
                    if (validationResult == null) {
                        validationResult = result;
                        validatedVersion = v;
                    }
                } catch (IOException e) {
                    // Continue to next version
                }
            }

            if (validationResult == null) {
                // Check if the requested version was invalid
                if (request.getVersion() != null && !request.getVersion().isEmpty() && 
                    !request.getVersion().equals(version) && !"latest".equals(request.getVersion())) {
                    // Version was explicitly requested but not found
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
                }
                // If no version was specified or it was "latest", and no schema was found, return 500
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }

            ValidationResponse response = ValidationResponse.builder()
                .valid(validationResult.isValid())
                .version(validatedVersion)
                .build();

            if (!validationResult.isValid()) {
                response.setErrors(validationResult.getErrors().stream()
                    .map(err -> ValidationResponse.ValidationError.builder()
                        .field(err.getField())
                        .message(err.getMessage())
                        .build())
                    .toList());
                
                if (config.getValidation().isStrictMode()) {
                    return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(response);
                }
            }

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/validate/bulk")
    public ResponseEntity<ValidateBulkEventsResponse> validateBulkEvents(@Valid @RequestBody ValidateBulkEventsRequest request) {
        try {
            if (request == null || request.getEvents() == null) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
            }
            
            // Empty array is allowed - return empty results
            if (request.getEvents().isEmpty()) {
                ValidateBulkEventsResponse.BulkSummary summary = ValidateBulkEventsResponse.BulkSummary.builder()
                    .total(0)
                    .valid(0)
                    .invalid(0)
                    .build();
                
                ValidateBulkEventsResponse bulkResponse = ValidateBulkEventsResponse.builder()
                    .results(new ArrayList<>())
                    .summary(summary)
                    .build();
                
                return ResponseEntity.ok(bulkResponse);
            }
            
            List<ValidationResponse> results = new ArrayList<>();
            int validCount = 0;
            int invalidCount = 0;

            for (Map<String, Object> event : request.getEvents()) {
                ValidationRequest singleRequest = new ValidationRequest();
                singleRequest.setEvent(event);
                singleRequest.setVersion(request.getVersion());
                
                ResponseEntity<ValidationResponse> response = validateEvent(singleRequest);
                ValidationResponse body = response.getBody();
                if (body != null) {
                    results.add(body);
                    if (body.isValid()) {
                        validCount++;
                    } else {
                        invalidCount++;
                    }
                }
            }

            ValidateBulkEventsResponse.BulkSummary summary = ValidateBulkEventsResponse.BulkSummary.builder()
                .total(request.getEvents().size())
                .valid(validCount)
                .invalid(invalidCount)
                .build();

            ValidateBulkEventsResponse bulkResponse = ValidateBulkEventsResponse.builder()
                .results(results)
                .summary(summary)
                .build();
            
            // In strict mode, if any events are invalid, return 422
            if (config.getValidation().isStrictMode() && invalidCount > 0) {
                return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(bulkResponse);
            }
            
            return ResponseEntity.ok(bulkResponse);
        } catch (org.springframework.web.bind.support.WebExchangeBindException e) {
            // Validation errors should be handled by GlobalExceptionHandler
            throw e;
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    private String determineVersion(String requestedVersion) throws IOException {
        if (requestedVersion == null || requestedVersion.isEmpty()) {
            requestedVersion = config.getValidation().getDefaultVersion();
        }
        if ("latest".equals(requestedVersion)) {
            List<String> versions = schemaCacheService.getVersions(gitSyncService.getLocalDir());
            if (versions.isEmpty()) {
                return "v1";
            }
            return versions.get(versions.size() - 1);
        }
        return requestedVersion;
    }
}
