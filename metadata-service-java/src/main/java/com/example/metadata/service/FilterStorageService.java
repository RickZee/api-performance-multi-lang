package com.example.metadata.service;

import com.example.metadata.exception.FilterNotFoundException;
import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterConditions;
import com.example.metadata.model.CreateFilterRequest;
import com.example.metadata.model.UpdateFilterRequest;
import com.example.metadata.repository.FilterRepository;
import com.example.metadata.repository.entity.FilterEntity;
import com.example.metadata.repository.mapper.FilterMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;

@Service
@Slf4j
public class FilterStorageService {
    private final FilterRepository filterRepository;
    private final FilterMapper filterMapper;
    private final SchemaCacheService schemaCacheService;
    private final String baseDir;
    
    // Feature flag for dual-write mode (write to both database and files during migration)
    @Value("${filter.storage.dual-write:false}")
    private boolean dualWriteEnabled;
    
    // Feature flag for fallback to file-based storage if database is empty
    @Value("${filter.storage.fallback-to-files:true}")
    private boolean fallbackToFilesEnabled;

    public FilterStorageService(
            FilterRepository filterRepository,
            FilterMapper filterMapper,
            GitSyncService gitSyncService,
            SchemaCacheService schemaCacheService) {
        this.filterRepository = filterRepository;
        this.filterMapper = filterMapper;
        this.schemaCacheService = schemaCacheService;
        this.baseDir = gitSyncService.getLocalDir();
    }

    @Transactional
    public Filter create(String schemaId, String schemaVersion, CreateFilterRequest request) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        String filterId = generateFilterId(request.getName());
        
        // Check if filter already exists
        if (filterRepository.existsByIdAndSchemaVersion(filterId, schemaVersion)) {
            throw new IOException("Filter with ID " + filterId + " already exists for schema version " + schemaVersion);
        }
        
        Instant now = Instant.now();
        // Default targets to ["flink", "spring"] for backward compatibility
        List<String> targets = request.getTargets();
        if (targets == null || targets.isEmpty()) {
            targets = new ArrayList<>(Arrays.asList("flink", "spring"));
        }
        
        // Ensure conditions has a default if not provided
        FilterConditions conditions = request.getConditions();
        if (conditions == null) {
            conditions = FilterConditions.builder()
                .logic("AND")
                .conditions(new ArrayList<>())
                .build();
        }
        
        Filter filter = Filter.builder()
                .id(filterId)
                .name(request.getName())
                .description(request.getDescription())
                .consumerGroup(request.getConsumerGroup())
                .outputTopic(request.getOutputTopic())
                .conditions(conditions)
                .enabled(request.isEnabled())
                .status("pending_approval")
                .targets(targets)
                .approvedForFlink(false)
                .approvedForSpring(false)
                .deployedToFlink(false)
                .deployedToSpring(false)
                .createdAt(now)
                .updatedAt(now)
                .version(1)
                .build();
        
        saveToDatabase(schemaId, schemaVersion, filter);
        
        // Dual-write mode: also write to files if enabled
        if (dualWriteEnabled) {
            try {
                saveToFiles(schemaVersion, filter);
            } catch (Exception e) {
                log.warn("Failed to write filter to files in dual-write mode: {}", e.getMessage());
            }
        }
        
        log.info("Filter created: schemaVersion={}, filterId={}, name={}", 
                schemaVersion, filterId, filter.getName());
        
        return filter;
    }

    public Filter get(String schemaId, String schemaVersion, String filterId) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        // Try database first
        Optional<FilterEntity> entityOpt = filterRepository.findByIdAndSchemaVersion(filterId, schemaVersion);
        if (entityOpt.isPresent()) {
            return filterMapper.toModel(entityOpt.get());
        }
        
        // Fallback to files if enabled and database is empty
        if (fallbackToFilesEnabled) {
            return getFromFiles(schemaVersion, filterId);
        }
        
        throw new FilterNotFoundException(filterId, schemaVersion);
    }

    public List<Filter> list(String schemaId, String schemaVersion) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        // Try database first
        List<FilterEntity> entities = filterRepository.findBySchemaVersion(schemaVersion);
        if (!entities.isEmpty()) {
            return filterMapper.toModelList(entities);
        }
        
        // Fallback to files if enabled and database is empty
        if (fallbackToFilesEnabled) {
            return listFromFiles(schemaVersion);
        }
        
        return List.of();
    }

    @Transactional
    public Filter update(String schemaId, String schemaVersion, String filterId, UpdateFilterRequest request) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        FilterEntity entity = filterRepository.findByIdAndSchemaVersion(filterId, schemaVersion)
                .orElseThrow(() -> new FilterNotFoundException(filterId, schemaVersion));
        
        Filter filter = filterMapper.toModel(entity);
        
        // Update fields if provided
        if (request.getName() != null) {
            filter.setName(request.getName());
        }
        if (request.getDescription() != null) {
            filter.setDescription(request.getDescription());
        }
        if (request.getConsumerGroup() != null) {
            filter.setConsumerGroup(request.getConsumerGroup());
        }
        if (request.getOutputTopic() != null) {
            filter.setOutputTopic(request.getOutputTopic());
        }
        if (request.getConditions() != null) {
            filter.setConditions(request.getConditions());
        }
        if (request.getEnabled() != null) {
            filter.setEnabled(request.getEnabled());
        }
        if (request.getTargets() != null && !request.getTargets().isEmpty()) {
            filter.setTargets(request.getTargets());
        }
        
        filter.setUpdatedAt(Instant.now());
        // Don't manually increment version - Hibernate @Version will handle it automatically
        
        saveToDatabase(schemaId, schemaVersion, filter);
        
        // Dual-write mode: also write to files if enabled
        if (dualWriteEnabled) {
            try {
                saveToFiles(schemaVersion, filter);
            } catch (Exception e) {
                log.warn("Failed to write filter to files in dual-write mode: {}", e.getMessage());
            }
        }
        
        log.info("Filter updated: schemaVersion={}, filterId={}", schemaVersion, filterId);
        
        return filter;
    }

    @Transactional
    public void delete(String schemaId, String schemaVersion, String filterId) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        FilterEntity entity = filterRepository.findByIdAndSchemaVersion(filterId, schemaVersion)
                .orElseThrow(() -> new FilterNotFoundException(filterId, schemaVersion));
        
        filterRepository.delete(entity);
        
        // Dual-write mode: also delete from files if enabled
        if (dualWriteEnabled) {
            try {
                deleteFromFiles(schemaVersion, filterId);
            } catch (Exception e) {
                log.warn("Failed to delete filter from files in dual-write mode: {}", e.getMessage());
            }
        }
        
        log.info("Filter deleted: schemaVersion={}, filterId={}", schemaVersion, filterId);
    }

    /**
     * Approve filter for a specific target (flink or spring).
     */
    @Transactional
    public Filter approveForTarget(String schemaId, String schemaVersion, String filterId, String target, String approvedBy) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        FilterEntity entity = filterRepository.findByIdAndSchemaVersion(filterId, schemaVersion)
                .orElseThrow(() -> new FilterNotFoundException(filterId, schemaVersion));
        
        Filter filter = filterMapper.toModel(entity);
        
        // Validate target
        if (!"flink".equals(target) && !"spring".equals(target)) {
            throw new IllegalArgumentException("Invalid target: " + target + ". Must be 'flink' or 'spring'");
        }
        
        // Check if filter has this target
        if (filter.getTargets() == null || !filter.getTargets().contains(target)) {
            throw new IOException("Filter does not have target: " + target);
        }
        
        // Check if already approved for this target
        if (("flink".equals(target) && Boolean.TRUE.equals(filter.getApprovedForFlink())) ||
            ("spring".equals(target) && Boolean.TRUE.equals(filter.getApprovedForSpring()))) {
            log.warn("Filter already approved for target: schemaVersion={}, filterId={}, target={}", 
                    schemaVersion, filterId, target);
            return filter;
        }
        
        Instant now = Instant.now();
        
        // Update approval status for the target
        if ("flink".equals(target)) {
            filter.setApprovedForFlink(true);
            filter.setApprovedForFlinkAt(now);
            filter.setApprovedForFlinkBy(approvedBy);
        } else {
            filter.setApprovedForSpring(true);
            filter.setApprovedForSpringAt(now);
            filter.setApprovedForSpringBy(approvedBy);
        }
        
        // Update overall status if both targets are approved
        if (Boolean.TRUE.equals(filter.getApprovedForFlink()) && Boolean.TRUE.equals(filter.getApprovedForSpring())) {
            filter.setStatus("approved");
            filter.setApprovedBy(approvedBy);
            filter.setApprovedAt(now);
        } else if (filter.getTargets().size() == 1) {
            // If only one target, set status to approved
            filter.setStatus("approved");
            filter.setApprovedBy(approvedBy);
            filter.setApprovedAt(now);
        }
        
        filter.setUpdatedAt(now);
        
        saveToDatabase(schemaId, schemaVersion, filter);
        
        // Dual-write mode: also write to files if enabled
        if (dualWriteEnabled) {
            try {
                saveToFiles(schemaVersion, filter);
            } catch (Exception e) {
                log.warn("Failed to write filter to files in dual-write mode: {}", e.getMessage());
            }
        }
        
        log.info("Filter approved for target: schemaVersion={}, filterId={}, target={}, approvedBy={}", 
                schemaVersion, filterId, target, approvedBy);
        
        return filter;
    }

    /**
     * Update deployment status for a specific target (flink or spring).
     */
    @Transactional
    public Filter updateDeploymentForTarget(String schemaId, String schemaVersion, String filterId, String target, 
                                            String status, List<String> statementIds, String error) throws IOException {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        FilterEntity entity = filterRepository.findByIdAndSchemaVersion(filterId, schemaVersion)
                .orElseThrow(() -> new FilterNotFoundException(filterId, schemaVersion));
        
        Filter filter = filterMapper.toModel(entity);
        
        // Validate target
        if (!"flink".equals(target) && !"spring".equals(target)) {
            throw new IllegalArgumentException("Invalid target: " + target + ". Must be 'flink' or 'spring'");
        }
        
        // Check if filter has this target
        if (filter.getTargets() == null || !filter.getTargets().contains(target)) {
            throw new IOException("Filter does not have target: " + target);
        }
        
        Instant now = Instant.now();
        
        // Update deployment status for the target
        if ("flink".equals(target)) {
            if ("deployed".equals(status)) {
                filter.setDeployedToFlink(true);
                filter.setDeployedToFlinkAt(now);
                filter.setFlinkStatementIds(statementIds);
                filter.setFlinkDeploymentError(null);
            } else if ("failed".equals(status)) {
                filter.setDeployedToFlink(false);
                filter.setFlinkDeploymentError(error);
            }
        } else {
            if ("deployed".equals(status)) {
                filter.setDeployedToSpring(true);
                filter.setDeployedToSpringAt(now);
                filter.setSpringDeploymentError(null);
            } else if ("failed".equals(status)) {
                filter.setDeployedToSpring(false);
                filter.setSpringDeploymentError(error);
            }
        }
        
        // Update overall status
        boolean allTargetsDeployed = true;
        if (filter.getTargets().contains("flink") && !Boolean.TRUE.equals(filter.getDeployedToFlink())) {
            allTargetsDeployed = false;
        }
        if (filter.getTargets().contains("spring") && !Boolean.TRUE.equals(filter.getDeployedToSpring())) {
            allTargetsDeployed = false;
        }
        
        if (allTargetsDeployed && filter.getTargets().size() > 0) {
            filter.setStatus("deployed");
            filter.setDeployedAt(now);
        } else if ("failed".equals(status)) {
            filter.setStatus("failed");
            filter.setDeploymentError(error);
        }
        
        filter.setUpdatedAt(now);
        
        saveToDatabase(schemaId, schemaVersion, filter);
        
        // Dual-write mode: also write to files if enabled
        if (dualWriteEnabled) {
            try {
                saveToFiles(schemaVersion, filter);
            } catch (Exception e) {
                log.warn("Failed to write filter to files in dual-write mode: {}", e.getMessage());
            }
        }
        
        log.info("Filter deployment updated for target: schemaVersion={}, filterId={}, target={}, status={}", 
                schemaVersion, filterId, target, status);
        
        return filter;
    }
    
    /**
     * Get active filters (enabled and not deleted) for a specific schema version.
     * Used by CDC Streaming Service for dynamic filter loading.
     */
    public List<Filter> getActiveFilters(String schemaId, String schemaVersion) {
        if (schemaId == null || schemaId.trim().isEmpty()) {
            throw new IllegalArgumentException("schemaId is required");
        }
        
        log.debug("Getting active filters for schema version: {}", schemaVersion);
        List<FilterEntity> entities = filterRepository.findActiveFiltersBySchemaVersion(schemaVersion);
        log.debug("Found {} active filter entities for schema version {}", entities.size(), schemaVersion);
        if (!entities.isEmpty()) {
            log.debug("Active filter IDs: {}", entities.stream().map(FilterEntity::getId).toList());
        }
        List<Filter> filters = filterMapper.toModelList(entities);
        log.info("Returning {} active filters for schema version {}", filters.size(), schemaVersion);
        return filters;
    }
    
    // Private helper methods
    
    private void saveToDatabase(String schemaId, String schemaVersion, Filter filter) {
        // Check if entity exists to preserve version for optimistic locking
        Optional<FilterEntity> existingEntity = filterRepository.findByIdAndSchemaVersion(filter.getId(), schemaVersion);
        
        FilterEntity entity;
        if (existingEntity.isPresent()) {
            // For updates, preserve the existing entity and update its fields
            entity = existingEntity.get();
            entity.setSchemaId(schemaId);
            entity.setName(filter.getName());
            entity.setDescription(filter.getDescription());
            entity.setConsumerGroup(filter.getConsumerGroup());
            entity.setOutputTopic(filter.getOutputTopic());
            entity.setConditions(filter.getConditions());
            entity.setEnabled(filter.isEnabled());
            entity.setStatus(filter.getStatus());
            entity.setUpdatedAt(filter.getUpdatedAt());
            entity.setApprovedBy(filter.getApprovedBy());
            entity.setApprovedAt(filter.getApprovedAt());
            entity.setDeployedAt(filter.getDeployedAt());
            entity.setDeploymentError(filter.getDeploymentError());
            entity.setFlinkStatementIds(filter.getFlinkStatementIds());
            entity.setSpringFilterId(filter.getSpringFilterId());
            entity.setTargets(filter.getTargets());
            entity.setApprovedForFlink(filter.getApprovedForFlink());
            entity.setApprovedForSpring(filter.getApprovedForSpring());
            entity.setApprovedForFlinkAt(filter.getApprovedForFlinkAt());
            entity.setApprovedForFlinkBy(filter.getApprovedForFlinkBy());
            entity.setApprovedForSpringAt(filter.getApprovedForSpringAt());
            entity.setApprovedForSpringBy(filter.getApprovedForSpringBy());
            entity.setDeployedToFlink(filter.getDeployedToFlink());
            entity.setDeployedToFlinkAt(filter.getDeployedToFlinkAt());
            entity.setDeployedToSpring(filter.getDeployedToSpring());
            entity.setDeployedToSpringAt(filter.getDeployedToSpringAt());
            entity.setFlinkDeploymentError(filter.getFlinkDeploymentError());
            entity.setSpringDeploymentError(filter.getSpringDeploymentError());
            // Version will be automatically incremented by Hibernate @Version
        } else {
            // For new entities, use mapper
            entity = filterMapper.toEntity(filter, schemaId, schemaVersion);
        }
        
        filterRepository.save(entity);
    }
    
    private String generateFilterId(String name) {
        // Convert name to kebab-case and add timestamp for uniqueness
        String kebabCase = name.toLowerCase()
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("^-|-$", "");
        return kebabCase + "-" + System.currentTimeMillis();
    }
    
    // File-based storage methods (for backward compatibility and migration)
    
    private Filter getFromFiles(String schemaVersion, String filterId) throws IOException {
        var schema = schemaCacheService.loadVersion(schemaVersion, baseDir);
        return schema.getFilters().stream()
                .filter(f -> f.getId().equals(filterId))
                .findFirst()
                .orElseThrow(() -> new FilterNotFoundException(filterId, schemaVersion));
    }
    
    private List<Filter> listFromFiles(String schemaVersion) throws IOException {
        var schema = schemaCacheService.loadVersion(schemaVersion, baseDir);
        return schema.getFilters();
    }
    
    private void saveToFiles(String schemaVersion, Filter filter) throws IOException {
        // This method maintains compatibility with file-based storage during migration
        // Implementation can be added if needed for dual-write mode
        log.debug("Dual-write mode: saving filter to files (schemaVersion={}, filterId={})", 
                schemaVersion, filter.getId());
        // Note: Full implementation would require the original file I/O logic
        // For now, we'll rely on database as primary storage
    }
    
    private void deleteFromFiles(String schemaVersion, String filterId) throws IOException {
        // This method maintains compatibility with file-based storage during migration
        log.debug("Dual-write mode: deleting filter from files (schemaVersion={}, filterId={})", 
                schemaVersion, filterId);
        // Note: Full implementation would require the original file I/O logic
        // For now, we'll rely on database as primary storage
    }
}
