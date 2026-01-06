package com.example.metadata.controller;

import com.example.metadata.config.AppConfig;
import com.example.metadata.exception.FilterNotFoundException;
import com.example.metadata.model.*;
import com.example.metadata.service.FilterDeployerService;
import com.example.metadata.service.FilterGeneratorService;
import com.example.metadata.service.FilterStorageService;
import com.example.metadata.service.JenkinsTriggerService;
import com.example.metadata.service.SpringYamlGeneratorService;
import com.example.metadata.service.SpringYamlWriterService;
import lombok.RequiredArgsConstructor;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/api/v1/filters")
@RequiredArgsConstructor
public class FilterController {
    private final FilterStorageService filterStorageService;
    private final FilterGeneratorService filterGeneratorService;
    private final FilterDeployerService filterDeployerService;
    private final SpringYamlGeneratorService springYamlGeneratorService;
    private final SpringYamlWriterService springYamlWriterService;
    private final JenkinsTriggerService jenkinsTriggerService;
    private final AppConfig config;

    @PostMapping
    public ResponseEntity<Filter> createFilter(
            @Valid @RequestBody CreateFilterRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.create(version, request);
            
            // Update Spring Boot YAML file
            updateSpringYaml(version);
            
            // Trigger CI/CD for change management
            jenkinsTriggerService.triggerSimpleBuild("create", filter.getId(), version);
            
            return ResponseEntity.status(HttpStatus.CREATED).body(filter);
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @GetMapping
    public ResponseEntity<List<Filter>> listFilters(
            @RequestParam(required = false, defaultValue = "v1") String version,
            @RequestParam(required = false) Boolean enabled,
            @RequestParam(required = false) String status
    ) {
        try {
            List<Filter> filters = filterStorageService.list(version);
            
            // Apply query parameter filters
            if (enabled != null) {
                filters = filters.stream()
                    .filter(f -> f.isEnabled() == enabled)
                    .toList();
            }
            if (status != null) {
                filters = filters.stream()
                    .filter(f -> status.equals(f.getStatus()))
                    .toList();
            }
            
            return ResponseEntity.ok(filters);
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @GetMapping("/{id}")
    public ResponseEntity<Filter> getFilter(
            @PathVariable String id,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Validate filter ID to prevent path traversal
            if (id == null || id.contains("..") || id.contains("/") || id.contains("\\")) {
                return ResponseEntity.notFound().build();
            }
            Filter filter = filterStorageService.get(version, id);
            return ResponseEntity.ok(filter);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            // If IOException is thrown, it might be because the filter doesn't exist
            // Check if it's a file not found or path issue
            if (e.getMessage() != null && (e.getMessage().contains("not found") || 
                e.getMessage().contains("No such file"))) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<Filter> updateFilter(
            @PathVariable String id,
            @RequestBody UpdateFilterRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.update(version, id, request);
            
            // Update Spring Boot YAML file
            updateSpringYaml(version);
            
            // Trigger CI/CD for change management
            jenkinsTriggerService.triggerSimpleBuild("update", id, version);
            
            return ResponseEntity.ok(filter);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteFilter(
            @PathVariable String id,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            filterStorageService.delete(version, id);
            
            // Update Spring Boot YAML file
            updateSpringYaml(version);
            
            // Trigger CI/CD for change management
            jenkinsTriggerService.triggerSimpleBuild("delete", id, version);
            
            return ResponseEntity.noContent().build();
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @GetMapping("/{id}/sql")
    public ResponseEntity<GenerateSQLResponse> getFilterSQL(
            @PathVariable String id,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(version, id);
            GenerateSQLResponse response = filterGeneratorService.generateSQL(filter);
            return ResponseEntity.ok(response);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/{id}/validations")
    public ResponseEntity<ValidateSQLResponse> createValidation(
            @PathVariable String id,
            @Valid @RequestBody ValidateSQLRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Verify filter exists
            filterStorageService.get(version, id);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
        
        // Basic SQL validation - check for common syntax errors
        ValidateSQLResponse response = ValidateSQLResponse.builder()
            .valid(true)
            .build();

        String sql = request.getSql();
        if (sql == null || sql.trim().isEmpty()) {
            response.setValid(false);
            response.setErrors(List.of("SQL is empty"));
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        }

        // Basic validation checks
        List<String> errors = new java.util.ArrayList<>();
        if (!sql.toUpperCase().contains("CREATE TABLE")) {
            errors.add("SQL must contain CREATE TABLE statement");
        }
        if (!sql.toUpperCase().contains("INSERT INTO")) {
            errors.add("SQL must contain INSERT INTO statement");
        }

        if (!errors.isEmpty()) {
            response.setValid(false);
            response.setErrors(errors);
        }

        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PatchMapping("/{id}")
    public ResponseEntity<Filter> updateFilterStatus(
            @PathVariable String id,
            @RequestBody(required = false) UpdateFilterStatusRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter;
            
            if (request != null && request.getStatus() != null) {
                String newStatus = request.getStatus();
                
                // Handle status updates
                if ("approved".equals(newStatus)) {
                    String approvedBy = request.getApprovedBy() != null ? request.getApprovedBy() : "system";
                    filter = filterStorageService.approve(version, id, approvedBy);
                    
                    // Trigger CI/CD for change management (approval may trigger validation pipeline)
                    java.util.Map<String, String> params = new java.util.HashMap<>();
                    params.put("APPROVED_BY", approvedBy);
                    jenkinsTriggerService.triggerBuild("approve", id, version, params);
                } else {
                    // For other status updates, we'd need a more generic updateStatus method
                    // For now, only support "approved" status via PATCH
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
                }
            } else {
                // If no status provided, return current filter
                filter = filterStorageService.get(version, id);
            }
            
            return ResponseEntity.ok(filter);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/{id}/deployments")
    public ResponseEntity<DeployFilterResponse> createDeployment(
            @PathVariable String id,
            @RequestBody(required = false) DeployFilterRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(version, id);

            // Check if filter is approved (unless force is true)
            if (request == null || !request.isForce()) {
                if (!"approved".equals(filter.getStatus())) {
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(DeployFilterResponse.builder()
                            .filterId(id)
                            .status("failed")
                            .error("Filter must be approved before deployment")
                            .build());
                }
            }

            // Check if Confluent Cloud credentials are configured
            if (!filterDeployerService.validateConnection()) {
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(DeployFilterResponse.builder()
                        .filterId(id)
                        .status("failed")
                        .error("Confluent Cloud credentials not configured")
                        .build());
            }

            // Generate SQL
            GenerateSQLResponse sqlResponse = filterGeneratorService.generateSQL(filter);
            if (!sqlResponse.isValid()) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(DeployFilterResponse.builder()
                        .filterId(id)
                        .status("failed")
                        .error("Failed to generate valid SQL: " + String.join(", ", sqlResponse.getValidationErrors()))
                        .build());
            }

            // Extract statement names
            List<String> statementNames = filterDeployerService.extractStatementNames(sqlResponse.getSql());

            // Deploy statements
            try {
                List<String> statementIds = filterDeployerService.deployStatements(
                    sqlResponse.getStatements(),
                    statementNames
                );

                // Update filter with deployment info
                filterStorageService.updateDeployment(version, id, "deployed", statementIds, null);

                // Update Spring Boot YAML file after successful deployment
                updateSpringYaml(version);

                // Trigger CI/CD for change management (deployment verification pipeline)
                java.util.Map<String, String> params = new java.util.HashMap<>();
                params.put("DEPLOYMENT_STATUS", "success");
                params.put("FLINK_STATEMENT_IDS", String.join(",", statementIds));
                jenkinsTriggerService.triggerBuild("deploy", id, version, params);

                return ResponseEntity.status(HttpStatus.CREATED).body(DeployFilterResponse.builder()
                    .filterId(id)
                    .status("deployed")
                    .flinkStatementIds(statementIds)
                    .message("Filter deployed successfully")
                    .build());
            } catch (IOException e) {
                filterStorageService.updateDeployment(version, id, "failed", null, e.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(DeployFilterResponse.builder()
                        .filterId(id)
                        .status("failed")
                        .error(e.getMessage())
                        .build());
            }
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }


    /**
     * Update Spring Boot filters.yml file with current filters.
     * This method is called after create, update, delete, and deploy operations.
     * Errors are logged but do not fail the API operation.
     */
    private void updateSpringYaml(String version) {
        if (!springYamlWriterService.isEnabled()) {
            return;
        }

        try {
            // Get all filters for the version
            List<Filter> filters = filterStorageService.list(version);
            
            // Generate YAML
            String yaml = springYamlGeneratorService.generateYaml(filters);
            
            // Write to file
            springYamlWriterService.writeFiltersYaml(yaml);
        } catch (IOException e) {
            // Log error but don't fail the API operation
            org.slf4j.LoggerFactory.getLogger(FilterController.class)
                .warn("Failed to update Spring Boot filters.yml: {}", e.getMessage());
        } catch (Exception e) {
            // Log any other errors
            org.slf4j.LoggerFactory.getLogger(FilterController.class)
                .warn("Unexpected error updating Spring Boot filters.yml: {}", e.getMessage(), e);
        }
    }
}
