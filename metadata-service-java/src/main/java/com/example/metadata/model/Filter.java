package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Filter {
    @JsonProperty("id")
    private String id;
    
    @JsonProperty("schemaId")
    private String schemaId;
    
    @JsonProperty("name")
    private String name;
    
    @JsonProperty("description")
    private String description;
    
    @JsonProperty("consumerGroup")
    private String consumerGroup;
    
    @JsonProperty("outputTopic")
    private String outputTopic;
    
    @JsonProperty("conditions")
    private FilterConditions conditions;
    
    @JsonProperty("enabled")
    private boolean enabled;
    
    @JsonProperty("status")
    private String status;
    
    @JsonProperty("createdAt")
    private Instant createdAt;
    
    @JsonProperty("updatedAt")
    private Instant updatedAt;
    
    @JsonProperty("approvedBy")
    private String approvedBy;
    
    @JsonProperty("approvedAt")
    private Instant approvedAt;
    
    @JsonProperty("deployedAt")
    private Instant deployedAt;
    
    @JsonProperty("deploymentError")
    private String deploymentError;
    
    @JsonProperty("flinkStatementIds")
    private List<String> flinkStatementIds;
    
    @JsonProperty("springFilterId")
    private String springFilterId;
    
    @JsonProperty("version")
    private int version;
    
    @JsonProperty("targets")
    private List<String> targets;
    
    @JsonProperty("approvedForFlink")
    private Boolean approvedForFlink;
    
    @JsonProperty("approvedForSpring")
    private Boolean approvedForSpring;
    
    @JsonProperty("approvedForFlinkAt")
    private Instant approvedForFlinkAt;
    
    @JsonProperty("approvedForFlinkBy")
    private String approvedForFlinkBy;
    
    @JsonProperty("approvedForSpringAt")
    private Instant approvedForSpringAt;
    
    @JsonProperty("approvedForSpringBy")
    private String approvedForSpringBy;
    
    @JsonProperty("deployedToFlink")
    private Boolean deployedToFlink;
    
    @JsonProperty("deployedToFlinkAt")
    private Instant deployedToFlinkAt;
    
    @JsonProperty("deployedToSpring")
    private Boolean deployedToSpring;
    
    @JsonProperty("deployedToSpringAt")
    private Instant deployedToSpringAt;
    
    @JsonProperty("flinkDeploymentError")
    private String flinkDeploymentError;
    
    @JsonProperty("springDeploymentError")
    private String springDeploymentError;
}
