package com.example.metadata.repository.entity;

import com.example.metadata.model.FilterCondition;
import com.example.metadata.repository.converter.FilterConditionsConverter;
import com.example.metadata.repository.converter.StringListConverter;
import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "filters", indexes = {
    @Index(name = "idx_filters_schema_version", columnList = "schema_version"),
    @Index(name = "idx_filters_status", columnList = "status"),
    @Index(name = "idx_filters_enabled", columnList = "enabled"),
    @Index(name = "idx_filters_schema_version_enabled", columnList = "schema_version,enabled"),
    @Index(name = "idx_filters_schema_version_status", columnList = "schema_version,status")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterEntity {
    
    @Id
    @Column(name = "id", length = 255)
    private String id;
    
    @Column(name = "schema_version", nullable = false, length = 50)
    private String schemaVersion;
    
    @Column(name = "name", nullable = false, length = 255)
    private String name;
    
    @Column(name = "description", columnDefinition = "TEXT")
    private String description;
    
    @Column(name = "consumer_id", length = 255)
    private String consumerId;
    
    @Column(name = "output_topic", nullable = false, length = 255)
    private String outputTopic;
    
    @Convert(converter = FilterConditionsConverter.class)
    @Column(name = "conditions", nullable = false, length = 10000)
    @Builder.Default
    private List<FilterCondition> conditions = new ArrayList<>();
    
    @Column(name = "enabled", nullable = false)
    @Builder.Default
    private Boolean enabled = true;
    
    @Column(name = "condition_logic", nullable = false, length = 10)
    @Builder.Default
    private String conditionLogic = "AND";
    
    @Column(name = "status", nullable = false, length = 50)
    @Builder.Default
    private String status = "pending_approval";
    
    @Version
    @Column(name = "version", nullable = false)
    @Builder.Default
    private Integer version = 1;
    
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
    
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;
    
    @Column(name = "approved_at")
    private Instant approvedAt;
    
    @Column(name = "approved_by", length = 255)
    private String approvedBy;
    
    @Column(name = "deployed_at")
    private Instant deployedAt;
    
    @Column(name = "deployment_error", columnDefinition = "TEXT")
    private String deploymentError;
    
    @Convert(converter = StringListConverter.class)
    @Column(name = "flink_statement_ids", length = 10000)
    private List<String> flinkStatementIds;
    
    @Convert(converter = StringListConverter.class)
    @Column(name = "targets", length = 10000)
    @Builder.Default
    private List<String> targets = new ArrayList<>();
    
    @Column(name = "approved_for_flink")
    @Builder.Default
    private Boolean approvedForFlink = false;
    
    @Column(name = "approved_for_spring")
    @Builder.Default
    private Boolean approvedForSpring = false;
    
    @Column(name = "approved_for_flink_at")
    private Instant approvedForFlinkAt;
    
    @Column(name = "approved_for_flink_by", length = 255)
    private String approvedForFlinkBy;
    
    @Column(name = "approved_for_spring_at")
    private Instant approvedForSpringAt;
    
    @Column(name = "approved_for_spring_by", length = 255)
    private String approvedForSpringBy;
    
    @Column(name = "deployed_to_flink")
    @Builder.Default
    private Boolean deployedToFlink = false;
    
    @Column(name = "deployed_to_flink_at")
    private Instant deployedToFlinkAt;
    
    @Column(name = "deployed_to_spring")
    @Builder.Default
    private Boolean deployedToSpring = false;
    
    @Column(name = "deployed_to_spring_at")
    private Instant deployedToSpringAt;
    
    @Column(name = "flink_deployment_error", columnDefinition = "TEXT")
    private String flinkDeploymentError;
    
    @Column(name = "spring_deployment_error", columnDefinition = "TEXT")
    private String springDeploymentError;
    
    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }
    
    @PreUpdate
    protected void onUpdate() {
        updatedAt = Instant.now();
    }
}

