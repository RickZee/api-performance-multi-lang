package io.debezium.connector.dsql.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Background scheduler for refreshing IAM tokens before they expire.
 * 
 * Schedules token refresh to occur before expiry, with exponential backoff
 * on refresh failures. Integrates with connection pool for seamless token rotation.
 */
public class TokenRefreshScheduler {
    private static final Logger LOGGER = LoggerFactory.getLogger(TokenRefreshScheduler.class);
    
    private static final long INITIAL_REFRESH_INTERVAL_MINUTES = 13; // Refresh 2 minutes before 15-min expiry
    private static final long MAX_REFRESH_INTERVAL_MINUTES = 14;
    private static final long BACKOFF_MULTIPLIER = 2;
    
    private final IamTokenGenerator tokenGenerator;
    private final ScheduledExecutorService scheduler;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private long currentRefreshInterval = INITIAL_REFRESH_INTERVAL_MINUTES;
    
    public TokenRefreshScheduler(IamTokenGenerator tokenGenerator) {
        this.tokenGenerator = tokenGenerator;
        this.scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "dsql-token-refresh-scheduler");
            t.setDaemon(true);
            return t;
        });
    }
    
    /**
     * Start the token refresh scheduler.
     */
    public void start() {
        if (running.compareAndSet(false, true)) {
            LOGGER.info("Starting IAM token refresh scheduler");
            scheduleNextRefresh();
        }
    }
    
    /**
     * Stop the token refresh scheduler.
     */
    public void stop() {
        if (running.compareAndSet(true, false)) {
            LOGGER.info("Stopping IAM token refresh scheduler");
            scheduler.shutdown();
            try {
                if (!scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                    scheduler.shutdownNow();
                }
            } catch (InterruptedException e) {
                scheduler.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }
    
    /**
     * Schedule the next token refresh.
     */
    private void scheduleNextRefresh() {
        if (!running.get()) {
            return;
        }
        
        scheduler.schedule(() -> {
            try {
                LOGGER.debug("Refreshing IAM token (scheduled refresh)");
                tokenGenerator.getToken(); // This will generate a new token if needed
                
                // Reset refresh interval on success
                currentRefreshInterval = INITIAL_REFRESH_INTERVAL_MINUTES;
                
                // Schedule next refresh
                scheduleNextRefresh();
            } catch (Exception e) {
                LOGGER.warn("Failed to refresh IAM token: {}. Retrying with exponential backoff.", e.getMessage());
                
                // Exponential backoff
                currentRefreshInterval = Math.min(
                    currentRefreshInterval * BACKOFF_MULTIPLIER,
                    MAX_REFRESH_INTERVAL_MINUTES
                );
                
                // Schedule retry
                scheduleNextRefresh();
            }
        }, currentRefreshInterval, TimeUnit.MINUTES);
    }
}

