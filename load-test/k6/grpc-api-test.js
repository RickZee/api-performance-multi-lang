/**
 * k6 gRPC API Throughput Test
 * Tests gRPC APIs (producer-api-grpc and producer-api-rust-grpc)
 */

import grpc from 'k6/net/grpc';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateGrpcEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = getTestOptions();

// Get API configuration from environment
const apiHost = __ENV.HOST || 'producer-api-grpc';
const apiPort = __ENV.PORT || 9090;
const serviceName = __ENV.SERVICE || 'com.example.grpc.EventService';
const methodName = __ENV.METHOD || 'ProcessEvent';
const protoFile = __ENV.PROTO_FILE || '/k6/proto/java-grpc/event_service.proto';

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

export default function () {
    // Connect to gRPC server (connection is reused across iterations)
    try {
        if (!client.connected) {
            console.log(`Connecting to gRPC server: ${apiHost}:${apiPort}`);
            client.connect(`${apiHost}:${apiPort}`, {
                plaintext: true,  // Use insecure connection (no TLS)
            });
            console.log(`Connected to gRPC server: ${client.connected}`);
        }
    } catch (e) {
        console.error(`Failed to connect to ${apiHost}:${apiPort}: ${e}`);
        errorRate.add(1);
        return;
    }
    
    // Generate event payload
    const payload = generateGrpcEventPayload();
    console.log(`Making gRPC call to ${serviceName}/${methodName}`);
    
    // Make gRPC call
    const response = client.invoke(`${serviceName}/${methodName}`, payload);
    console.log(`gRPC response received: status=${response ? response.status : 'null'}`);
    
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
    client.close();
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
    
    summary += '\n';
    return summary;
}

