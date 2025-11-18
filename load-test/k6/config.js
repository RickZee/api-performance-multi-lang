/**
 * k6 Test Configuration
 * Centralized configuration for all k6 throughput tests
 */

// Test mode: 'smoke', 'full', or 'saturation'
export const TEST_MODE = __ENV.TEST_MODE || 'smoke';

// API configurations
export const API_CONFIG = {
    'producer-api-java-rest': {
        protocol: 'http',
        host: __ENV.HOST || 'producer-api-java-rest',
        port: __ENV.PORT || 8081,
        path: '/api/v1/events',
    },
    'producer-api-rust-rest': {
        protocol: 'http',
        host: __ENV.HOST || 'producer-api-rust-rest',
        port: __ENV.PORT || 8081,
        path: '/api/v1/events',
    },
    'producer-api-go-rest': {
        protocol: 'http',
        host: __ENV.HOST || 'producer-api-go-rest',
        port: __ENV.PORT || 9083,
        path: '/api/v1/events',
    },
    'producer-api-java-grpc': {
        protocol: 'grpc',
        host: __ENV.HOST || 'producer-api-java-grpc',
        port: __ENV.PORT || 9090,
        service: 'com.example.grpc.EventService',
        method: 'ProcessEvent',
        protoFile: '/k6/proto/java-grpc/event_service.proto',
    },
    'producer-api-rust-grpc': {
        protocol: 'grpc',
        host: __ENV.HOST || 'producer-api-rust-grpc',
        port: __ENV.PORT || 9090,
        service: 'com.example.grpc.EventService',
        method: 'ProcessEvent',
        protoFile: '/k6/proto/rust-grpc/event_service.proto',
    },
    'producer-api-go-grpc': {
        protocol: 'grpc',
        host: __ENV.HOST || 'producer-api-go-grpc',
        port: __ENV.PORT || 9092,
        service: 'com.example.grpc.EventService',
        method: 'ProcessEvent',
        protoFile: '/k6/proto/go-grpc/event_service.proto',
    },
};

// Test phases configuration
export const TEST_PHASES = {
    smoke: [
        { duration: '10s', target: 5 },    // Phase 1: Baseline
        { duration: '10s', target: 10 },   // Phase 2: Mid-load
        { duration: '10s', target: 20 },   // Phase 3: High-load
        { duration: '10s', target: 30 },   // Phase 4: Higher-load
    ],
    full: [
        { duration: '2m', target: 10 },   // Phase 1: Baseline
        { duration: '2m', target: 50 },   // Phase 2: Mid-load
        { duration: '2m', target: 100 },  // Phase 3: High-load
        { duration: '5m', target: 200 },  // Phase 4: Higher-load
    ],
    saturation: [
        { duration: '2m', target: 10 },    // Phase 1: Baseline
        { duration: '2m', target: 100 },   // Phase 2: High-load
        { duration: '2m', target: 500 },   // Phase 3: Extreme
        { duration: '2m', target: 1000 },  // Phase 4: Maximum
        { duration: '2m', target: 2000 },  // Phase 5: Saturation
    ],
};

// Get test options based on mode
export function getTestOptions() {
    // Determine protocol from environment or default to http
    const protocol = __ENV.PROTOCOL || 'http';
    
    // Build thresholds based on protocol
    // Note: k6 will only validate thresholds for metrics that exist
    // For gRPC, we'll add thresholds only if requests are made
    const thresholds = {};
    if (protocol === 'http') {
        thresholds.http_req_duration = ['p(95)<2000', 'p(99)<5000'];  // 95% < 2s, 99% < 5s
        thresholds.http_req_failed = ['rate<0.05'];  // Error rate < 5%
    } else if (protocol === 'grpc') {
        // Only add gRPC thresholds if we expect gRPC requests
        // k6 will create these metrics when gRPC requests are made
        thresholds.grpc_req_duration = ['p(95)<2000', 'p(99)<5000'];
        // Don't add grpc_req_failed threshold - it will be created when requests are made
        // thresholds.grpc_req_failed = ['rate<0.05'];
    }
    
    const options = {};
    
    // For smoke tests, use 1 VU with 5 iterations (exactly 5 events)
    // For full and saturation tests, use stages to enable phase-based metrics collection
    if (TEST_MODE === 'smoke') {
        options.vus = 1;
        options.iterations = 5;
    } else {
        options.stages = TEST_PHASES[TEST_MODE] || TEST_PHASES.full;
    }
    
    // Only add thresholds if we have any
    if (Object.keys(thresholds).length > 0) {
        options.thresholds = thresholds;
    }
    
    return options;
}

