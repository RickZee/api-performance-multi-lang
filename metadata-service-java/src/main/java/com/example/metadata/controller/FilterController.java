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
import java.time.Instant;
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
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            List<Filter> filters = filterStorageService.list(version);
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

    @PostMapping("/{id}/generate")
    public ResponseEntity<GenerateSQLResponse> generateSQL(
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

    @PostMapping("/{id}/validate")
    public ResponseEntity<ValidateSQLResponse> validateSQL(
            @PathVariable String id,
            @RequestBody ValidateSQLRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        // Basic SQL validation - check for common syntax errors
        ValidateSQLResponse response = ValidateSQLResponse.builder()
            .valid(true)
            .build();

        String sql = request.getSql();
        if (sql == null || sql.trim().isEmpty()) {
            response.setValid(false);
            response.setErrors(List.of("SQL is empty"));
            return ResponseEntity.ok(response);
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

        return ResponseEntity.ok(response);
    }

    @PostMapping("/{id}/approve")
    public ResponseEntity<Filter> approveFilter(
            @PathVariable String id,
            @RequestBody(required = false) ApproveFilterRequest request,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            String approvedBy = request.getApprovedBy() != null ? request.getApprovedBy() : "system";
            Filter filter = filterStorageService.approve(version, id, approvedBy);
            
            // Trigger CI/CD for change management (approval may trigger validation pipeline)
            java.util.Map<String, String> params = new java.util.HashMap<>();
            params.put("APPROVED_BY", approvedBy);
            jenkinsTriggerService.triggerBuild("approve", id, version, params);
            
            return ResponseEntity.ok(filter);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/{id}/deploy")
    public ResponseEntity<DeployFilterResponse> deployFilter(
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

                return ResponseEntity.ok(DeployFilterResponse.builder()
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

    @GetMapping("/{id}/status")
    public ResponseEntity<FilterStatusResponse> getFilterStatus(
            @PathVariable String id,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(version, id);
            
            FilterStatusResponse response = FilterStatusResponse.builder()
                .filterId(id)
                .status(filter.getStatus())
                .flinkStatementIds(filter.getFlinkStatementIds())
                .deployedAt(filter.getDeployedAt())
                .deploymentError(filter.getDeploymentError())
                .lastChecked(Instant.now())
                .build();

            return ResponseEntity.ok(response);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get active filters (enabled and not deleted) for a specific schema version.
     * This endpoint is optimized for CDC Streaming Service consumption.
     * Returns only filters that should be actively used for event routing.
     * 
     * @param schemaVersion Schema version (e.g., "v1", "v2")
     * @return List of active filters
     */
    @GetMapping("/active")
    public ResponseEntity<List<Filter>> getActiveFilters(
            @RequestParam(value = "version", required = false, defaultValue = "v1") String schemaVersion
    ) {
        try {
            List<Filter> activeFilters = filterStorageService.getActiveFilters(schemaVersion);
            return ResponseEntity.ok(activeFilters);
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(FilterController.class)
                .error("Error retrieving active filters for schema version {}: {}", 
                    schemaVersion, e.getMessage(), e);
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
