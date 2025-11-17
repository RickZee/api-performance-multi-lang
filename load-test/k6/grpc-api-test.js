/**
 * k6 gRPC API Throughput Test
 * Tests gRPC APIs (producer-api-java-grpc, producer-api-rust-grpc, producer-api-go-grpc)
 */

import grpc from 'k6/net/grpc';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateGrpcEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');
const connectionAttempts = new Rate('connection_attempts');
const connectionFailures = new Rate('connection_failures');
const connectionRetries = new Rate('connection_retries');

// Test configuration
export const options = getTestOptions();

// Connection configuration
const MAX_RETRIES = 5;
const INITIAL_RETRY_DELAY_MS = 100;
const MAX_RETRY_DELAY_MS = 2000;
const CONNECTION_TIMEOUT_MS = 5000;

// Get API configuration from environment
const apiHost = __ENV.HOST || 'producer-api-java-grpc';
const apiPort = __ENV.PORT || 9090;
const serviceName = __ENV.SERVICE || 'com.example.grpc.EventService';
const methodName = __ENV.METHOD || 'ProcessEvent';
const protoFile = __ENV.PROTO_FILE || '/k6/proto/java-grpc/event_service.proto';

// Payload size is configured via PAYLOAD_SIZE environment variable (4k, 8k, 32k, 64k)
// If not specified, uses default small payload (~400-500 bytes)

// Create gRPC client
const client = new grpc.Client();

// Load proto file
// k6's grpc client.load() resolves paths relative to script location
// Scripts are at /k6/scripts, proto files are at /k6/proto
// So we need to use relative path: ../proto/java-grpc/event_service.proto
try {
    // Convert absolute path to relative path from script location (/k6/scripts)
    let protoPath = protoFile;
    if (protoFile.startsWith('/k6/proto/')) {
        // Convert /k6/proto/java-grpc/event_service.proto to ../proto/java-grpc/event_service.proto
        // Replace /k6/proto/ with ../proto/
        protoPath = protoFile.replace('/k6/proto/', '../proto/');
    } else if (protoFile.startsWith('/k6/')) {
        // Handle other /k6/ paths
        protoPath = protoFile.replace('/k6/', '../');
    } else if (!protoFile.startsWith('/')) {
        // Already relative, use as-is
        protoPath = protoFile;
    }
    
    // For import paths, use empty array - proto file should be self-contained
    // If proto has imports, we'd need to add the directory, but for now try without
    console.log(`Attempting to load proto file: ${protoPath}`);
    client.load([], protoPath);
    console.log(`Proto file loaded successfully: ${protoPath}`);
} catch (e) {
    console.error(`Failed to load proto file ${protoFile} as relative path: ${e}`);
    // Try with import path set to proto directory
    try {
        const protoPath = protoFile.startsWith('/k6/proto/') ? '../' + protoFile.substring(5) : protoFile;
        const protoDir = protoPath.substring(0, protoPath.lastIndexOf('/'));
        console.log(`Trying alternative: protoPath=${protoPath}, protoDir=${protoDir}`);
        client.load([protoDir], protoPath);
        console.log(`Alternative load succeeded`);
    } catch (e2) {
        console.error(`Alternative load with import path also failed: ${e2}`);
        throw e2; // Re-throw to fail the test
    }
}

/**
 * Generate exponential backoff delay with jitter
 * @param {number} attempt - Current retry attempt (0-indexed)
 * @returns {number} Delay in seconds
 */
function getRetryDelay(attempt) {
    const baseDelay = Math.min(INITIAL_RETRY_DELAY_MS * Math.pow(2, attempt), MAX_RETRY_DELAY_MS);
    // Add jitter: random value between 0 and 20% of base delay
    const jitter = baseDelay * 0.2 * Math.random();
    return (baseDelay + jitter) / 1000; // Convert to seconds for sleep()
}

// Initialize connection once per VU (k6 gRPC client is lazy - connection happens on first invoke)
let connectionInitialized = false;

/**
 * Initialize gRPC connection (lazy - actual connection happens on first invoke)
 * k6's gRPC client.connect() is lazy and doesn't actually connect until first invoke()
 */
function initializeConnection() {
    if (connectionInitialized) {
        return true;
    }
    
    const vuId = __VU || 'unknown';
    try {
        // Call connect() - this is lazy, actual connection happens on first invoke
        client.connect(`${apiHost}:${apiPort}`, {
            plaintext: true,  // Use insecure connection (no TLS)
            timeout: CONNECTION_TIMEOUT_MS / 1000, // Convert to seconds
        });
        connectionInitialized = true;
        console.log(`[TCP] VU ${vuId}: Connection initialized (lazy) to ${apiHost}:${apiPort}`);
        return true;
    } catch (e) {
        const errorMsg = e.toString();
        console.error(`[TCP] VU ${vuId}: Failed to initialize connection: ${errorMsg}`);
        connectionFailures.add(1);
        return false;
    }
}

export default function () {
    const vuId = __VU || 'unknown';
    const iterId = __ITER || 'unknown';
    
    // Initialize connection (lazy - actual connection happens on first invoke)
    if (!initializeConnection()) {
        console.error(`[TCP] VU ${vuId} Iter ${iterId}: Cannot initialize connection, skipping request`);
        errorRate.add(1);
        return;
    }
    
    // Generate event payload (size controlled by PAYLOAD_SIZE env var)
    const payload = generateGrpcEventPayload();
    
    // Make gRPC call with retry logic
    // k6's gRPC client.connect() is lazy - actual connection happens on first invoke()
    let response;
    
    // Track connection attempt once per iteration
    connectionAttempts.add(1);
    
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            if (attempt > 0) {
                connectionRetries.add(1);
                const delay = getRetryDelay(attempt - 1);
                console.log(`[TCP] VU ${vuId} Iter ${iterId}: Retry attempt ${attempt}/${MAX_RETRIES} after ${(delay * 1000).toFixed(0)}ms delay`);
                sleep(delay);
                
                // Reset connection on retry
                try {
                    if (client.connected) {
                        client.close();
                    }
                } catch (e) {
                    // Ignore close errors
                }
                connectionInitialized = false;
                if (!initializeConnection()) {
                    continue;
                }
            }
            
            console.log(`[TCP] VU ${vuId} Iter ${iterId}: Invoking gRPC method (attempt ${attempt + 1}/${MAX_RETRIES})...`);
            response = client.invoke(`${serviceName}/${methodName}`, payload);
            
            // Success - break out of retry loop
            break;
        } catch (e) {
            const errorMsg = e.toString();
            console.error(`[TCP] VU ${vuId} Iter ${iterId}: gRPC invoke attempt ${attempt + 1} failed: ${errorMsg}`);
            
            // Check if it's a connection exhaustion error
            if (errorMsg.includes('cannot assign requested address') || 
                errorMsg.includes('address already in use') ||
                errorMsg.includes('EADDRNOTAVAIL') ||
                errorMsg.includes('EADDRINUSE')) {
                
                console.error(`[TCP] VU ${vuId} Iter ${iterId}: PORT EXHAUSTION DETECTED - ${errorMsg}`);
                
                // For connection exhaustion, use longer backoff
                if (attempt < MAX_RETRIES - 1) {
                    const delay = getRetryDelay(attempt) * 2; // Double delay for port exhaustion
                    console.log(`[TCP] VU ${vuId} Iter ${iterId}: Using extended backoff ${(delay * 1000).toFixed(0)}ms for port exhaustion`);
                    sleep(delay);
                    continue;
                }
            }
            
            // For other errors, continue retry loop
            if (attempt < MAX_RETRIES - 1) {
                continue;
            } else {
                // Last attempt failed
                connectionFailures.add(1);
                console.error(`[TCP] VU ${vuId} Iter ${iterId}: FAILED after ${MAX_RETRIES} attempts: ${errorMsg}`);
                errorRate.add(1);
                return;
            }
        }
    }
    
    // If we get here without a response, it's an error
    if (!response) {
        connectionFailures.add(1);
        console.error(`[TCP] VU ${vuId} Iter ${iterId}: No response after all retries`);
        errorRate.add(1);
        return;
    }
    
    // Check response
    const success = check(response, {
        'status is OK': (r) => r && r.status === grpc.StatusOK,
        'response has success field': (r) => r && r.message && r.message.success !== undefined,
    });
    
    if (!success) {
        console.error(`gRPC call failed: response=${JSON.stringify(response)}`);
    }
    
    errorRate.add(!success);
    
    // Small sleep to avoid overwhelming the server
    sleep(0.1);
}

export function teardown(data) {
    const vuId = __VU || 'unknown';
    try {
        if (client && client.connected) {
            console.log(`[TCP] VU ${vuId}: Closing connection during teardown`);
            client.close();
        } else {
            console.log(`[TCP] VU ${vuId}: No active connection to close during teardown`);
        }
    } catch (e) {
        console.log(`[TCP] VU ${vuId}: Error during teardown (ignored): ${e}`);
        // Ignore errors during teardown
    }
}

export function handleSummary(data) {
    return {
        'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    };
}

function textSummary(data, options) {
    const indent = options.indent || '';
    const enableColors = options.enableColors || false;
    
    let summary = '\n';
    summary += `${indent}Test Summary\n`;
    summary += `${indent}============\n\n`;
    
    // gRPC metrics
    if (data.metrics.grpc_reqs) {
        const grpcReqs = data.metrics.grpc_reqs;
        summary += `${indent}gRPC Requests:\n`;
        summary += `${indent}  Total: ${grpcReqs.values.count}\n`;
        summary += `${indent}  Rate: ${grpcReqs.values.rate.toFixed(2)} req/s\n`;
    }
    
    if (data.metrics.grpc_req_duration) {
        const duration = data.metrics.grpc_req_duration;
        summary += `${indent}Response Time:\n`;
        if (duration.values && duration.values.avg !== undefined) {
            summary += `${indent}  Avg: ${duration.values.avg.toFixed(2)}ms\n`;
            summary += `${indent}  Min: ${duration.values.min.toFixed(2)}ms\n`;
            summary += `${indent}  Max: ${duration.values.max.toFixed(2)}ms\n`;
            if (duration.values['p(95)'] !== undefined) {
                summary += `${indent}  P95: ${duration.values['p(95)'].toFixed(2)}ms\n`;
            }
            if (duration.values['p(99)'] !== undefined) {
                summary += `${indent}  P99: ${duration.values['p(99)'].toFixed(2)}ms\n`;
            }
        }
    }
    
    if (data.metrics.grpc_req_failed) {
        const failed = data.metrics.grpc_req_failed;
        summary += `${indent}Error Rate: ${(failed.values.rate * 100).toFixed(2)}%\n`;
    }
    
    // Connection metrics
    if (data.metrics.connection_attempts) {
        const attempts = data.metrics.connection_attempts;
        summary += `${indent}Connection Attempts: ${attempts.values.count}\n`;
    }
    
    if (data.metrics.connection_failures) {
        const failures = data.metrics.connection_failures;
        summary += `${indent}Connection Failures: ${failures.values.count}\n`;
        if (failures.values.count > 0) {
            summary += `${indent}Connection Failure Rate: ${(failures.values.rate * 100).toFixed(2)}%\n`;
        }
    }
    
    if (data.metrics.connection_retries) {
        const retries = data.metrics.connection_retries;
        summary += `${indent}Connection Retries: ${retries.values.count}\n`;
    }
    
    summary += '\n';
    return summary;
}

