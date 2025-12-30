package com.example.streamprocessor.service;

import com.example.streamprocessor.config.FilterConfig;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.function.Consumer;

/**
 * Service that polls Metadata Service API for filter updates and reloads filters dynamically.
 * Detects changes by comparing filter versions/timestamps and reloads when changes are detected.
 */
@Service
@Slf4j
@ConditionalOnProperty(name = "metadata.service.enabled", havingValue = "true", matchIfMissing = false)
public class DynamicFilterLoaderService {
    
    private final MetadataServiceClient metadataServiceClient;
    private final String schemaVersion;
    private final boolean enabled;
    
    // Current filters state
    private final Map<String, FilterConfig> currentFilters = new ConcurrentHashMap<>();
    private final ReentrantReadWriteLock lock = new ReentrantReadWriteLock();
    
    // Listeners for filter change events
    private final List<Consumer<List<FilterConfig>>> filterChangeListeners = new ArrayList<>();
    
    // Track last update timestamp for change detection
    private long lastUpdateTimestamp = 0;
    
    public DynamicFilterLoaderService(
            MetadataServiceClient metadataServiceClient,
            @Value("${metadata.service.schema.version:v1}") String schemaVersion,
            @Value("${metadata.service.enabled:false}") boolean enabled) {
        this.metadataServiceClient = metadataServiceClient;
        this.schemaVersion = schemaVersion;
        this.enabled = enabled;
    }
    
    @PostConstruct
    public void initialize() {
        if (!enabled) {
            log.info("Dynamic filter loading is disabled");
            return;
        }
        
        log.info("Initializing dynamic filter loader for schema version: {}", schemaVersion);
        
        // Initial load of filters
        try {
            loadFilters();
        } catch (Exception e) {
            log.error("Failed to load filters during initialization: {}", e.getMessage(), e);
        }
    }
    
    /**
     * Poll Metadata Service API for filter updates.
     * Runs at configurable interval (default: 30 seconds).
     */
    @Scheduled(fixedDelayString = "${metadata.service.poll.interval:30000}")
    public void pollForUpdates() {
        if (!enabled) {
            return;
        }
        
        if (!metadataServiceClient.isAvailable()) {
            log.warn("Metadata Service is not available, skipping filter update");
            return;
        }
        
        try {
            loadFilters();
        } catch (Exception e) {
            log.error("Error polling for filter updates: {}", e.getMessage(), e);
        }
    }
    
    /**
     * Load filters from Metadata Service and detect changes.
     */
    private void loadFilters() {
        try {
            List<FilterConfig> newFilters = metadataServiceClient.fetchActiveFilters(schemaVersion);
            
            lock.writeLock().lock();
            try {
                // Detect changes by comparing filter IDs and versions
                boolean hasChanges = detectChanges(newFilters);
                
                if (hasChanges) {
                    log.info("Filter changes detected, updating filter configuration");
                    
                    // Update current filters
                    currentFilters.clear();
                    for (FilterConfig filter : newFilters) {
                        currentFilters.put(filter.getId(), filter);
                    }
                    
                    lastUpdateTimestamp = System.currentTimeMillis();
                    
                    // Notify listeners of filter changes
                    notifyFilterChangeListeners(new ArrayList<>(newFilters));
                    
                    log.info("Updated {} active filters", newFilters.size());
                } else {
                    log.debug("No filter changes detected");
                }
            } finally {
                lock.writeLock().unlock();
            }
        } catch (Exception e) {
            log.error("Failed to load filters: {}", e.getMessage(), e);
            throw e;
        }
    }
    
    /**
     * Detect if filters have changed by comparing current and new filter lists.
     */
    private boolean detectChanges(List<FilterConfig> newFilters) {
        // Quick check: different sizes
        if (currentFilters.size() != newFilters.size()) {
            return true;
        }
        
        // Check for new or removed filters
        Set<String> currentIds = currentFilters.keySet();
        Set<String> newIds = new HashSet<>();
        for (FilterConfig filter : newFilters) {
            newIds.add(filter.getId());
        }
        
        if (!currentIds.equals(newIds)) {
            return true;
        }
        
        // Check for version changes in existing filters
        for (FilterConfig newFilter : newFilters) {
            FilterConfig currentFilter = currentFilters.get(newFilter.getId());
            if (currentFilter == null) {
                return true; // New filter
            }
            
            // Compare versions if available
            if (newFilter.getVersion() != null && currentFilter.getVersion() != null) {
                if (!newFilter.getVersion().equals(currentFilter.getVersion())) {
                    return true; // Version changed
                }
            }
        }
        
        return false;
    }
    
    /**
     * Get current active filters.
     * Thread-safe read operation.
     */
    public List<FilterConfig> getCurrentFilters() {
        lock.readLock().lock();
        try {
            return new ArrayList<>(currentFilters.values());
        } finally {
            lock.readLock().unlock();
        }
    }
    
    /**
     * Register a listener for filter change events.
     * Listeners are notified when filters are updated.
     */
    public void addFilterChangeListener(Consumer<List<FilterConfig>> listener) {
        synchronized (filterChangeListeners) {
            filterChangeListeners.add(listener);
        }
    }
    
    /**
     * Notify all registered listeners of filter changes.
     */
    private void notifyFilterChangeListeners(List<FilterConfig> filters) {
        synchronized (filterChangeListeners) {
            for (Consumer<List<FilterConfig>> listener : filterChangeListeners) {
                try {
                    listener.accept(filters);
                } catch (Exception e) {
                    log.error("Error notifying filter change listener: {}", e.getMessage(), e);
                }
            }
        }
    }
    
    /**
     * Manually trigger a filter reload.
     * Useful for testing or manual refresh.
     */
    public void reloadFilters() {
        if (!enabled) {
            log.warn("Dynamic filter loading is disabled, cannot reload filters");
            return;
        }
        
        log.info("Manually triggering filter reload");
        loadFilters();
    }
    
    /**
     * Get the last update timestamp.
     */
    public long getLastUpdateTimestamp() {
        lock.readLock().lock();
        try {
            return lastUpdateTimestamp;
        } finally {
            lock.readLock().unlock();
        }
    }
}

