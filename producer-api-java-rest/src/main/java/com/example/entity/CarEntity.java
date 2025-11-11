package com.example.entity;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.OffsetDateTime;

@Table("car_entities")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CarEntity {

    @Id
    @Column("id")
    private String id;

    @Column("entity_type")
    private String entityType;

    @Column("created_at")
    private OffsetDateTime createdAt;

    @Column("updated_at")
    private OffsetDateTime updatedAt;

    @Column("data")
    private String data; // Store as JSON string for R2DBC
}
