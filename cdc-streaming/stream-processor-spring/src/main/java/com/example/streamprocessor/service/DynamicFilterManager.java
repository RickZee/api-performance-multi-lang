package com.example.streamprocessor.service;

import com.example.streamprocessor.config.FilterConfig;
import com.example.streamprocessor.model.EventHeader;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.function.Predicate;

/**
 * Manages dynamic filters for event routing.
 * Filters can be updated at runtime without restarting the stream processor.
 */
@Service
@Slf4j
public class DynamicFilterManager {
    
    // Map of filter ID to output topic and predicate
    private final Map<String, FilterRoutingInfo> activeFilters = new ConcurrentHashMap<>();
    private final ReentrantReadWriteLock lock = new ReentrantReadWriteLock();
    
    /**
     * Update filters with new configuration.
     * Thread-safe operation that replaces all filters atomically.
     */
    public void updateFilters(List<FilterConfig> filters) {
        lock.writeLock().lock();
        try {
            log.info("Updating {} filters in DynamicFilterManager", filters.size());
            
            // Build new filter map
            Map<String, FilterRoutingInfo> newFilters = new HashMap<>();
            
            for (FilterConfig filterConfig : filters) {
                if (filterConfig == null || filterConfig.getId() == null || filterConfig.getOutputTopic() == null) {
                    log.warn("Skipping invalid filter configuration");
                    continue;
                }
                
                // Skip disabled or deleted filters
                if (Boolean.FALSE.equals(filterConfig.getEnabled()) 
                        || "deleted".equals(filterConfig.getStatus())
                        || "pending_deletion".equals(filterConfig.getStatus())) {
                    continue;
                }
                
                // Add -spring suffix if not already present
                String outputTopic = filterConfig.getOutputTopic().endsWith("-spring") 
                        ? filterConfig.getOutputTopic() 
                        : filterConfig.getOutputTopic() + "-spring";
                
                // Create predicate from filter conditions
                Predicate<EventHeader> predicate = com.example.streamprocessor.config.FilterConditionEvaluator
                        .createPredicate(filterConfig);
                
                newFilters.put(filterConfig.getId(), new FilterRoutingInfo(outputTopic, predicate, filterConfig));
            }
            
            // Atomically replace all filters
            activeFilters.clear();
            activeFilters.putAll(newFilters);
            
            log.info("Updated {} active filters", activeFilters.size());
        } finally {
            lock.writeLock().unlock();
        }
    }
    
    /**
     * Get all output topics that should receive events.
     * Thread-safe read operation.
     */
    public Set<String> getOutputTopics() {
        lock.readLock().lock();
        try {
            Set<String> topics = new HashSet<>();
            for (FilterRoutingInfo info : activeFilters.values()) {
                topics.add(info.outputTopic);
            }
            return topics;
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Get output topics for a given event.
     * Returns all topics where the event matches filter conditions.
     * Thread-safe read operation.
     */
    public Set<String> getOutputTopicsForEvent(EventHeader event) {
        if (event == null) {
            return Collections.emptySet();
        }
        
        lock.readLock().lock();
        try {
            Set<String> matchingTopics = new HashSet<>();
            for (FilterRoutingInfo info : activeFilters.values()) {
                if (info.predicate.test(event)) {
                    matchingTopics.add(info.outputTopic);
                }
            }
            return matchingTopics;
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Get current filter count.
     */
    public int getFilterCount() {
        lock.readLock().lock();
        try {
            return activeFilters.size();
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Internal class to hold filter routing information.
     */
    private static class FilterRoutingInfo {
        final String outputTopic;
        final Predicate<EventHeader> predicate;
        final FilterConfig config;
        
        FilterRoutingInfo(String outputTopic, Predicate<EventHeader> predicate, FilterConfig config) {
            this.outputTopic = outputTopic;
            this.predicate = predicate;
            this.config = config;
        }
    }
}

