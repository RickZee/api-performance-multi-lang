package com.example.repository;

import com.example.entity.CarEntity;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Mono;

@Repository
public interface CarEntityRepository extends ReactiveCrudRepository<CarEntity, String> {
    
    Mono<CarEntity> findByEntityTypeAndId(String entityType, String id);
    
    Mono<Boolean> existsByEntityTypeAndId(String entityType, String id);
}
