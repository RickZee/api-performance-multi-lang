package com.example.metadata.repository.mapper;

import com.example.metadata.model.Filter;
import com.example.metadata.repository.entity.FilterEntity;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class FilterMapper {
    
    /**
     * Convert FilterEntity to Filter model
     */
    public Filter toModel(FilterEntity entity) {
        if (entity == null) {
            return null;
        }
        
        return Filter.builder()
                .id(entity.getId())
                .name(entity.getName())
                .description(entity.getDescription())
                .consumerId(entity.getConsumerId())
                .outputTopic(entity.getOutputTopic())
                .conditions(entity.getConditions())
                .enabled(entity.getEnabled())
                .conditionLogic(entity.getConditionLogic())
                .status(entity.getStatus())
                .version(entity.getVersion())
                .createdAt(entity.getCreatedAt())
                .updatedAt(entity.getUpdatedAt())
                .approvedBy(entity.getApprovedBy())
                .approvedAt(entity.getApprovedAt())
                .deployedAt(entity.getDeployedAt())
                .deploymentError(entity.getDeploymentError())
                .flinkStatementIds(entity.getFlinkStatementIds())
                .targets(entity.getTargets())
                .approvedForFlink(entity.getApprovedForFlink())
                .approvedForSpring(entity.getApprovedForSpring())
                .approvedForFlinkAt(entity.getApprovedForFlinkAt())
                .approvedForFlinkBy(entity.getApprovedForFlinkBy())
                .approvedForSpringAt(entity.getApprovedForSpringAt())
                .approvedForSpringBy(entity.getApprovedForSpringBy())
                .deployedToFlink(entity.getDeployedToFlink())
                .deployedToFlinkAt(entity.getDeployedToFlinkAt())
                .deployedToSpring(entity.getDeployedToSpring())
                .deployedToSpringAt(entity.getDeployedToSpringAt())
                .flinkDeploymentError(entity.getFlinkDeploymentError())
                .springDeploymentError(entity.getSpringDeploymentError())
                .build();
    }
    
    /**
     * Convert Filter model to FilterEntity
     */
    public FilterEntity toEntity(Filter model, String schemaVersion) {
        if (model == null) {
            return null;
        }
        
        return FilterEntity.builder()
                .id(model.getId())
                .schemaVersion(schemaVersion)
                .name(model.getName())
                .description(model.getDescription())
                .consumerId(model.getConsumerId())
                .outputTopic(model.getOutputTopic())
                .conditions(model.getConditions())
                .enabled(model.isEnabled())
                .conditionLogic(model.getConditionLogic())
                .status(model.getStatus())
                .version(model.getVersion())
                .createdAt(model.getCreatedAt())
                .updatedAt(model.getUpdatedAt())
                .approvedBy(model.getApprovedBy())
                .approvedAt(model.getApprovedAt())
                .deployedAt(model.getDeployedAt())
                .deploymentError(model.getDeploymentError())
                .flinkStatementIds(model.getFlinkStatementIds())
                .targets(model.getTargets())
                .approvedForFlink(model.getApprovedForFlink())
                .approvedForSpring(model.getApprovedForSpring())
                .approvedForFlinkAt(model.getApprovedForFlinkAt())
                .approvedForFlinkBy(model.getApprovedForFlinkBy())
                .approvedForSpringAt(model.getApprovedForSpringAt())
                .approvedForSpringBy(model.getApprovedForSpringBy())
                .deployedToFlink(model.getDeployedToFlink())
                .deployedToFlinkAt(model.getDeployedToFlinkAt())
                .deployedToSpring(model.getDeployedToSpring())
                .deployedToSpringAt(model.getDeployedToSpringAt())
                .flinkDeploymentError(model.getFlinkDeploymentError())
                .springDeploymentError(model.getSpringDeploymentError())
                .build();
    }
    
    /**
     * Convert list of FilterEntity to list of Filter
     */
    public List<Filter> toModelList(List<FilterEntity> entities) {
        if (entities == null) {
            return null;
        }
        return entities.stream()
                .map(this::toModel)
                .toList();
    }
    
}

