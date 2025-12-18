package com.example.repository;

import com.example.entity.SimpleEventEntity;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface SimpleEventRepository extends ReactiveCrudRepository<SimpleEventEntity, String> {
}

