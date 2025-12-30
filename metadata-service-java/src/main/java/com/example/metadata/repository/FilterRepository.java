package com.example.metadata.repository;

import com.example.metadata.repository.entity.FilterEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface FilterRepository extends JpaRepository<FilterEntity, String> {
    
    /**
     * Find all filters for a specific schema version
     */
    List<FilterEntity> findBySchemaVersion(String schemaVersion);
    
    /**
     * Find filters by schema version and status
     */
    List<FilterEntity> findBySchemaVersionAndStatus(String schemaVersion, String status);
    
    /**
     * Find enabled filters for a specific schema version
     */
    List<FilterEntity> findBySchemaVersionAndEnabledTrue(String schemaVersion);
    
    /**
     * Find filters by status (across all schema versions)
     */
    List<FilterEntity> findByStatusIn(List<String> statuses);
    
    /**
     * Find active filters (enabled and not deleted) for a specific schema version
     * Used by CDC Streaming Service for dynamic filter loading
     * Active filters are those that are approved or deployed, enabled, and not deleted
     */
    @Query("SELECT f FROM FilterEntity f WHERE f.schemaVersion = :schemaVersion " +
           "AND f.enabled = true AND f.status IN ('approved', 'deployed')")
    List<FilterEntity> findActiveFiltersBySchemaVersion(@Param("schemaVersion") String schemaVersion);
    
    /**
     * Check if a filter exists by ID and schema version
     */
    boolean existsByIdAndSchemaVersion(String id, String schemaVersion);
    
    /**
     * Find a filter by ID and schema version
     */
    Optional<FilterEntity> findByIdAndSchemaVersion(String id, String schemaVersion);
}

