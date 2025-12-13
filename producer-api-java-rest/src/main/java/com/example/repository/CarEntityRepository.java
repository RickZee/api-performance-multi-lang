package com.example.repository;

import com.example.entity.CarEntity;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

@Repository
public interface CarEntityRepository extends ReactiveCrudRepository<CarEntity, String> {
    
    Mono<CarEntity> findByEntityTypeAndEntityId(String entityType, String entityId);
    
    Mono<Boolean> existsByEntityTypeAndEntityId(String entityType, String entityId);
}
