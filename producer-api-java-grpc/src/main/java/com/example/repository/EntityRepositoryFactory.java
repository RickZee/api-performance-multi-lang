package com.example.repository;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
public class EntityRepositoryFactory {
    
    private final DatabaseClient databaseClient;
    private final ObjectMapper objectMapper;
    
    // Entity type to table name mapping
    private static final Map<String, String> ENTITY_TABLE_MAP = Map.of(
            "Car", "car_entities",
            "Loan", "loan_entities",
            "LoanPayment", "loan_payment_entities",
            "ServiceRecord", "service_record_entities"
    );

    public EntityRepositoryFactory(DatabaseClient databaseClient, ObjectMapper objectMapper) {
        this.databaseClient = databaseClient;
        this.objectMapper = objectMapper;
    }

    public EntityRepository getRepository(String entityType) {
        String tableName = ENTITY_TABLE_MAP.get(entityType);
        if (tableName == null) {
            return null;
        }
        return new EntityRepository(databaseClient, objectMapper, tableName);
    }
}

