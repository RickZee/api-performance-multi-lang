package com.example.entity;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.OffsetDateTime;

@Table("simple_events")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class SimpleEventEntity {

    @Id
    @Column("id")
    private String id;

    @Column("event_name")
    private String eventName;

    @Column("created_date")
    private OffsetDateTime createdDate;

    @Column("saved_date")
    private OffsetDateTime savedDate;

    @Column("event_type")
    private String eventType;
}








