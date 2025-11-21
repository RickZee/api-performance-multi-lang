/**
 * k6 Lambda gRPC API Throughput Test
 * Tests Lambda gRPC APIs via API Gateway HTTP API with gRPC-Web protocol
 * Supports: producer-api-go-grpc-lambda, producer-api-java-grpc-lambda
 * 
 * Note: Lambda gRPC APIs use gRPC-Web protocol over HTTP, not native gRPC
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateGrpcEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');
const coldStartRate = new Rate('cold_starts');

// Test configuration
export const options = getTestOptions();

// Get API configuration from environment
// For Lambda gRPC APIs, we use API Gateway HTTP API endpoints with gRPC-Web
// Priority: API_URL > LAMBDA_API_URL > default
const apiUrl = __ENV.API_URL || __ENV.LAMBDA_API_URL || 'http://localhost:9085';
const serviceName = __ENV.SERVICE || 'com.example.grpc.EventService';
const methodName = __ENV.METHOD || 'ProcessEvent';

// gRPC-Web path format: /<service>/<method>
const grpcWebPath = `/${serviceName}/${methodName}`;
const fullApiUrl = `${apiUrl}${grpcWebPath}`;

// Payload size is configured via PAYLOAD_SIZE environment variable (4k, 8k, 32k, 64k)
// If not specified, uses default small payload (~400-500 bytes)

// Track cold starts by detecting higher latency on first request
const COLD_START_THRESHOLD_MS = 500; // Threshold to detect potential cold starts

/**
 * Encode gRPC-Web message
 * gRPC-Web uses a simple binary format:
 * - 1 byte: flags (0x00 for data, 0x80 for trailer)
 * - 4 bytes: length (big-endian)
 * - N bytes: protobuf message
 */
function encodeGrpcWebMessage(protobufData) {
    // For simplicity, we'll send JSON and let the Lambda handle conversion
    // In production, you'd encode as protobuf binary
    // This is a simplified version - actual gRPC-Web requires protobuf encoding
    const jsonData = JSON.stringify(protobufData);
    const dataBuffer = new TextEncoder().encode(jsonData);
    
    // gRPC-Web frame format (simplified - actual implementation needs protobuf)
    // Flag byte (0x00 = data)
    const flag = new Uint8Array([0x00]);
    
    // Length (4 bytes, big-endian)
    const length = new Uint8Array(4);
    const view = new DataView(length.buffer);
    view.setUint32(0, dataBuffer.length, false); // big-endian
    
    // Combine: flag + length + data
    const frame = new Uint8Array(1 + 4 + dataBuffer.length);
    frame.set(flag, 0);
    frame.set(length, 1);
    frame.set(dataBuffer, 5);
    
    return frame;
}

export default function () {
    // Generate gRPC event payload (size controlled by PAYLOAD_SIZE env var)
    const payload = generateGrpcEventPayload();
    
    // For gRPC-Web, we can send JSON if the Lambda supports it
    // Otherwise, we need to encode as protobuf binary
    // For now, we'll send as JSON with gRPC-Web headers
    const jsonPayload = JSON.stringify(payload);
    
    // Set headers for gRPC-Web over HTTP
    const params = {
        headers: {
            'Content-Type': 'application/grpc-web+json', // JSON variant of gRPC-Web
            'Accept': 'application/grpc-web+json',
            'X-Grpc-Web': '1',
        },
        tags: {
            name: 'Lambda gRPC API (gRPC-Web)',
        },
    };
    
    // Send POST request (gRPC-Web uses POST)
    const res = http.post(fullApiUrl, jsonPayload, params);
    
    // Detect potential cold start
    const isPotentialColdStart = res.timings.duration > COLD_START_THRESHOLD_MS;
    if (isPotentialColdStart) {
        coldStartRate.add(1);
    } else {
        coldStartRate.add(0);
    }
    
    // Check response
    // gRPC-Web responses may have different status codes
    // 200 OK is typical for successful gRPC-Web responses
    const success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 30s': (r) => r.timings.duration < 30000, // Lambda timeout is typically 30s
        'response has body': (r) => r.body && r.body.length > 0,
    });
    
    errorRate.add(!success);
    
    // Small sleep to avoid overwhelming the API Gateway
    sleep(0.1);
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
    summary += `${indent}Lambda gRPC API (gRPC-Web) Test Summary\n`;
    summary += `${indent}=====================================\n\n`;
    
    // HTTP metrics (gRPC-Web uses HTTP)
    if (data.metrics.http_reqs) {
        const httpReqs = data.metrics.http_reqs;
        summary += `${indent}HTTP Requests (gRPC-Web):\n`;
        summary += `${indent}  Total: ${httpReqs.values.count}\n`;
        summary += `${indent}  Rate: ${httpReqs.values.rate.toFixed(2)} req/s\n`;
    }
    
    if (data.metrics.http_req_duration) {
        const duration = data.metrics.http_req_duration;
        summary += `${indent}Response Time:\n`;
        if (duration.values) {
            if (duration.values.avg !== undefined) {
                summary += `${indent}  Avg: ${duration.values.avg.toFixed(2)}ms\n`;
            }
            if (duration.values.min !== undefined) {
                summary += `${indent}  Min: ${duration.values.min.toFixed(2)}ms\n`;
            }
            if (duration.values.max !== undefined) {
                summary += `${indent}  Max: ${duration.values.max.toFixed(2)}ms\n`;
            }
            if (duration.values['p(95)'] !== undefined) {
                summary += `${indent}  P95: ${duration.values['p(95)'].toFixed(2)}ms\n`;
            }
            if (duration.values['p(99)'] !== undefined) {
                summary += `${indent}  P99: ${duration.values['p(99)'].toFixed(2)}ms\n`;
            }
        }
    }
    
    if (data.metrics.http_req_failed) {
        const failed = data.metrics.http_req_failed;
        summary += `${indent}Error Rate: ${(failed.values.rate * 100).toFixed(2)}%\n`;
    }
    
    // Cold start detection (heuristic)
    if (data.metrics.cold_starts) {
        const coldStarts = data.metrics.cold_starts;
        summary += `${indent}Potential Cold Starts: ${coldStarts.values.count} (${(coldStarts.values.rate * 100).toFixed(2)}%)\n`;
        summary += `${indent}  Note: Actual cold starts should be verified via CloudWatch Logs\n`;
    }
    
    summary += '\n';
    return summary;
}

