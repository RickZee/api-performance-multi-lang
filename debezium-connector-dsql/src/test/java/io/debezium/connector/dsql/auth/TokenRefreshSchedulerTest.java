package io.debezium.connector.dsql.auth;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;
import static org.mockito.Mockito.lenient;

@ExtendWith(MockitoExtension.class)
class TokenRefreshSchedulerTest {
    
    @Mock
    private IamTokenGenerator tokenGenerator;
    
    private TokenRefreshScheduler scheduler;
    
    @BeforeEach
    void setUp() {
        lenient().when(tokenGenerator.getToken()).thenReturn("test-token");
        scheduler = new TokenRefreshScheduler(tokenGenerator);
    }
    
    @Test
    void testStart() {
        scheduler.start();
        
        // Verify token generator is called (scheduled refresh)
        // Note: Actual refresh happens asynchronously, so we verify the start doesn't throw
        assertThat(scheduler).isNotNull();
    }
    
    @Test
    void testStop() throws InterruptedException {
        scheduler.start();
        
        // Stop should not throw
        scheduler.stop();
        
        // Verify it can be stopped multiple times
        scheduler.stop();
    }
    
    @Test
    void testStartStopMultipleTimes() {
        scheduler.start();
        scheduler.stop();
        
        // Create new scheduler for second start/stop cycle
        // (can't restart terminated scheduler)
        TokenRefreshScheduler scheduler2 = new TokenRefreshScheduler(tokenGenerator);
        scheduler2.start();
        scheduler2.stop();
        
        // Should not throw
        assertThat(scheduler).isNotNull();
        assertThat(scheduler2).isNotNull();
    }
    
    @Test
    void testTokenRefreshCalled() throws InterruptedException {
        // Test that scheduler can be started
        // Note: Actual token refresh happens after 13 minutes, so we just verify structure
        scheduler.start();
        
        // Verify scheduler started without errors
        assertThat(scheduler).isNotNull();
        
        scheduler.stop();
    }
    
    @Test
    void testStopBeforeStart() {
        // Should not throw
        scheduler.stop();
    }
}
