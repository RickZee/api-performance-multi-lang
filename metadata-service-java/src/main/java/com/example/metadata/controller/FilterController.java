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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.create(schemaId, version, request);
            
            // Update Spring Boot YAML file only if filter targets include spring
            if (filter.getTargets() != null && filter.getTargets().contains("spring")) {
                updateSpringYaml(schemaId, version);
            }
            
            // Trigger CI/CD for change management
            jenkinsTriggerService.triggerSimpleBuild("create", filter.getId(), version);
            
            return ResponseEntity.status(HttpStatus.CREATED).body(filter);
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @GetMapping
    public ResponseEntity<List<Filter>> listFilters(
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version,
            @RequestParam(required = false) Boolean enabled,
            @RequestParam(required = false) String status
    ) {
        try {
            List<Filter> filters = filterStorageService.list(schemaId, version);
            
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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Validate filter ID to prevent path traversal
            if (id == null || id.contains("..") || id.contains("/") || id.contains("\\")) {
                return ResponseEntity.notFound().build();
            }
            Filter filter = filterStorageService.get(schemaId, version, id);
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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.update(schemaId, version, id, request);
            
            // Update Spring Boot YAML file only if filter targets include spring
            if (filter.getTargets() != null && filter.getTargets().contains("spring")) {
                updateSpringYaml(schemaId, version);
            }
            
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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Get filter before deleting to check targets
            Filter filter = filterStorageService.get(schemaId, version, id);
            filterStorageService.delete(schemaId, version, id);
            
            // Update Spring Boot YAML file only if filter targeted spring
            if (filter.getTargets() != null && filter.getTargets().contains("spring")) {
                updateSpringYaml(schemaId, version);
            }
            
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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(schemaId, version, id);
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
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Verify filter exists
            filterStorageService.get(schemaId, version, id);
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


    @PatchMapping("/{id}/approvals/{target}")
    public ResponseEntity<Filter> approveFilterForTarget(
            @PathVariable String id,
            @PathVariable String target,
            @Valid @RequestBody ApproveFilterRequest request,
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Validate target
            if (!"flink".equals(target) && !"spring".equals(target)) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
            }
            
            String approvedBy = request.getApprovedBy() != null ? request.getApprovedBy() : "system";
            Filter filter = filterStorageService.approveForTarget(schemaId, version, id, target, approvedBy);
            
            // Trigger CI/CD for change management
            java.util.Map<String, String> params = new java.util.HashMap<>();
            params.put("APPROVED_BY", approvedBy);
            params.put("TARGET", target);
            jenkinsTriggerService.triggerBuild("approve", id, version, params);
            
            return ResponseEntity.ok(filter);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
    
    @GetMapping("/{id}/approvals")
    public ResponseEntity<FilterApprovalStatus> getFilterApprovals(
            @PathVariable String id,
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(schemaId, version, id);
            
            FilterApprovalStatus.TargetApprovalStatus flinkStatus = FilterApprovalStatus.TargetApprovalStatus.builder()
                    .approved(filter.getApprovedForFlink())
                    .approvedAt(filter.getApprovedForFlinkAt())
                    .approvedBy(filter.getApprovedForFlinkBy())
                    .build();
            
            FilterApprovalStatus.TargetApprovalStatus springStatus = FilterApprovalStatus.TargetApprovalStatus.builder()
                    .approved(filter.getApprovedForSpring())
                    .approvedAt(filter.getApprovedForSpringAt())
                    .approvedBy(filter.getApprovedForSpringBy())
                    .build();
            
            FilterApprovalStatus status = FilterApprovalStatus.builder()
                    .flink(flinkStatus)
                    .spring(springStatus)
                    .build();
            
            return ResponseEntity.ok(status);
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
    
    @PostMapping("/{id}/deployments/{target}")
    public ResponseEntity<DeployFilterResponse> createDeploymentForTarget(
            @PathVariable String id,
            @PathVariable String target,
            @RequestBody(required = false) DeployFilterRequest request,
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            // Validate target
            if (!"flink".equals(target) && !"spring".equals(target)) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(DeployFilterResponse.builder()
                                .filterId(id)
                                .status("failed")
                                .error("Invalid target: " + target + ". Must be 'flink' or 'spring'")
                                .build());
            }
            
            Filter filter = filterStorageService.get(schemaId, version, id);
            
            // Check if filter has this target
            if (filter.getTargets() == null || !filter.getTargets().contains(target)) {
                return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                        .body(DeployFilterResponse.builder()
                                .filterId(id)
                                .status("failed")
                                .error("Filter does not have target: " + target)
                                .build());
            }
            
            // Check if filter is approved for this target (unless force is true)
            if (request == null || !request.isForce()) {
                boolean isApproved = "flink".equals(target) 
                        ? Boolean.TRUE.equals(filter.getApprovedForFlink())
                        : Boolean.TRUE.equals(filter.getApprovedForSpring());
                
                if (!isApproved) {
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(DeployFilterResponse.builder()
                                    .filterId(id)
                                    .status("failed")
                                    .error("Filter must be approved for " + target + " before deployment")
                                    .build());
                }
            }
            
            if ("flink".equals(target)) {
                // Check if local Flink is enabled
                boolean useLocalFlink = config.getFlink() != null && 
                                       config.getFlink().getLocal() != null && 
                                       config.getFlink().getLocal().isEnabled();
                
                if (useLocalFlink) {
                    // Deploy to local Flink
                    if (!filterDeployerService.validateLocalFlinkConnection()) {
                        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                                .body(DeployFilterResponse.builder()
                                        .filterId(id)
                                        .status("failed")
                                        .error("Local Flink cluster is not available")
                                        .build());
                    }
                } else {
                    // Deploy to Confluent Cloud Flink
                if (!filterDeployerService.validateConnection()) {
                    return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                            .body(DeployFilterResponse.builder()
                                    .filterId(id)
                                    .status("failed")
                                    .error("Confluent Cloud credentials not configured")
                                    .build());
                    }
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
                    List<String> statementIds;
                    if (useLocalFlink) {
                        statementIds = filterDeployerService.deployToLocalFlink(
                                sqlResponse.getStatements(),
                                statementNames
                        );
                    } else {
                        statementIds = filterDeployerService.deployStatements(
                            sqlResponse.getStatements(),
                            statementNames
                    );
                    }
                    
                    // Update filter with deployment info
                    filterStorageService.updateDeploymentForTarget(schemaId, version, id, target, "deployed", statementIds, null);
                    
                    // Trigger CI/CD for change management
                    java.util.Map<String, String> params = new java.util.HashMap<>();
                    params.put("DEPLOYMENT_STATUS", "success");
                    params.put("TARGET", target);
                    params.put("FLINK_STATEMENT_IDS", String.join(",", statementIds));
                    params.put("FLINK_TYPE", useLocalFlink ? "local" : "confluent");
                    jenkinsTriggerService.triggerBuild("deploy", id, version, params);
                    
                    return ResponseEntity.status(HttpStatus.CREATED).body(DeployFilterResponse.builder()
                            .filterId(id)
                            .status("deployed")
                            .flinkStatementIds(statementIds)
                            .message("Filter deployed successfully to " + target + (useLocalFlink ? " (local)" : " (Confluent Cloud)"))
                            .build());
                } catch (IOException e) {
                    filterStorageService.updateDeploymentForTarget(schemaId, version, id, target, "failed", null, e.getMessage());
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(DeployFilterResponse.builder()
                                    .filterId(id)
                                    .status("failed")
                                    .error(e.getMessage())
                                    .build());
                }
            } else {
                // Deploy to Spring Boot (update filters.yml)
                try {
                    // Update Spring Boot YAML file
                    updateSpringYaml(schemaId, version);
                    
                    // Update filter with deployment info
                    filterStorageService.updateDeploymentForTarget(schemaId, version, id, target, "deployed", null, null);
                    
                    // Trigger CI/CD for change management
                    java.util.Map<String, String> params = new java.util.HashMap<>();
                    params.put("DEPLOYMENT_STATUS", "success");
                    params.put("TARGET", target);
                    jenkinsTriggerService.triggerBuild("deploy", id, version, params);
                    
                    return ResponseEntity.status(HttpStatus.CREATED).body(DeployFilterResponse.builder()
                            .filterId(id)
                            .status("deployed")
                            .message("Filter deployed successfully to " + target)
                            .build());
                } catch (Exception e) {
                    filterStorageService.updateDeploymentForTarget(schemaId, version, id, target, "failed", null, e.getMessage());
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(DeployFilterResponse.builder()
                                    .filterId(id)
                                    .status("failed")
                                    .error(e.getMessage())
                                    .build());
                }
            }
        } catch (FilterNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (IllegalArgumentException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(DeployFilterResponse.builder()
                            .filterId(id)
                            .status("failed")
                            .error(e.getMessage())
                            .build());
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
    
    @GetMapping("/{id}/deployments")
    public ResponseEntity<FilterDeploymentStatus> getFilterDeployments(
            @PathVariable String id,
            @RequestParam(required = true) String schemaId,
            @RequestParam(required = false, defaultValue = "v1") String version
    ) {
        try {
            Filter filter = filterStorageService.get(schemaId, version, id);
            
            FilterDeploymentStatus.TargetDeploymentStatus flinkStatus = FilterDeploymentStatus.TargetDeploymentStatus.builder()
                    .deployed(filter.getDeployedToFlink())
                    .deployedAt(filter.getDeployedToFlinkAt())
                    .statementIds(filter.getFlinkStatementIds())
                    .error(filter.getFlinkDeploymentError())
                    .build();
            
            FilterDeploymentStatus.TargetDeploymentStatus springStatus = FilterDeploymentStatus.TargetDeploymentStatus.builder()
                    .deployed(filter.getDeployedToSpring())
                    .deployedAt(filter.getDeployedToSpringAt())
                    .error(filter.getSpringDeploymentError())
                    .build();
            
            FilterDeploymentStatus status = FilterDeploymentStatus.builder()
                    .flink(flinkStatus)
                    .spring(springStatus)
                    .build();
            
            return ResponseEntity.ok(status);
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
    private void updateSpringYaml(String schemaId, String version) {
        if (!springYamlWriterService.isEnabled()) {
            return;
        }

        try {
            // Get all filters for the version
            List<Filter> filters = filterStorageService.list(schemaId, version);
            
            // Filter to only include Spring Boot targets
            List<Filter> springFilters = filters.stream()
                    .filter(f -> f.getTargets() != null && f.getTargets().contains("spring"))
                    .toList();
            
            // Generate YAML
            String yaml = springYamlGeneratorService.generateYaml(springFilters);
            
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
