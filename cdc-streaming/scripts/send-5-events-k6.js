/**
 * k6 Script to Send 5 Events Total to Python Lambda API
 * 
 * Sends 5 events total:
 * 1. CarCreated (2 events)
 * 2. LoanCreated (1 event)
 * 3. LoanPaymentSubmitted (1 event)
 * 4. CarServiceDone (1 event)
 * 
 * Total: 5 events
 * 
 * Flow: k6 → Python Lambda API → Aurora PostgreSQL → CDC → Confluent Cloud → Flink → Filtered Topics → Consumers
 * 
 * Usage:
 *   k6 run --env LAMBDA_PYTHON_REST_API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com send-5-events-k6.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const eventsSent = new Rate('events_sent');

// Test configuration - send 5 events total
const TOTAL_EVENTS = 5;
export const options = {
    vus: 1,
    iterations: TOTAL_EVENTS, // 5 total events
};

// Get API configuration from environment
const apiUrl = __ENV.LAMBDA_PYTHON_REST_API_URL || __ENV.API_URL || __ENV.LAMBDA_API_URL || 'https://k5z0vg8boa.execute-api.us-east-1.amazonaws.com';
const apiPath = '/api/v1/events';
const fullApiUrl = `${apiUrl}${apiPath}`;

// Generate UUID
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

// Generate ISO 8601 timestamp
function generateTimestamp() {
    return new Date().toISOString();
}

// Generate CarCreated event
function generateCarCreatedEvent(carId = null) {
    const timestamp = generateTimestamp();
    const id = carId || `CAR-${Date.now()}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "CarCreated",
            eventType: "CarCreated",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
                entityType: "Car",
                entityId: id,
                updatedAttributes: {
                    id: id,
                    vin: `VIN${randomString(17).toUpperCase()}`,
                    make: ["Tesla", "Toyota", "Honda", "Ford"][randomIntBetween(0, 3)],
                    model: ["Model S", "Camry", "Accord", "F-150"][randomIntBetween(0, 3)],
                    year: randomIntBetween(2020, 2025),
                    color: ["Red", "Blue", "Black", "White"][randomIntBetween(0, 3)],
                    mileage: randomIntBetween(0, 50000),
                    status: "active"
                }
            }]
        }
    });
}

// Generate LoanCreated event
function generateLoanCreatedEvent(carId, loanId = null) {
    const timestamp = generateTimestamp();
    const id = loanId || `LOAN-${Date.now()}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "LoanCreated",
            eventType: "LoanCreated",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
                entityType: "Loan",
                entityId: id,
                updatedAttributes: {
                    id: id,
                    carId: carId,
                    loanAmount: randomIntBetween(20000, 60000),
                    balance: randomIntBetween(20000, 60000),
                    interestRate: 0.045,
                    termMonths: 60,
                    status: "active",
                    monthlyPayment: randomIntBetween(400, 1200)
                }
            }]
        }
    });
}

// Generate LoanPaymentSubmitted event
function generateLoanPaymentEvent(loanId, paymentId = null) {
    const timestamp = generateTimestamp();
    const id = paymentId || `PAYMENT-${Date.now()}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "LoanPaymentSubmitted",
            eventType: "LoanPaymentSubmitted",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
                entityType: "LoanPayment",
                entityId: id,
                updatedAttributes: {
                    id: id,
                    loanId: loanId,
                    amount: randomIntBetween(400, 1200),
                    paymentDate: timestamp,
                    status: "completed"
                }
            }]
        }
    });
}

// Generate CarServiceDone event
function generateCarServiceEvent(carId, serviceId = null) {
    const timestamp = generateTimestamp();
    const id = serviceId || `SERVICE-${Date.now()}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "CarServiceDone",
            eventType: "CarServiceDone",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
                entityType: "ServiceRecord",
                entityId: id,
                updatedAttributes: {
                    id: id,
                    carId: carId,
                    serviceDate: timestamp,
                    amountPaid: randomIntBetween(200, 500),
                    dealerName: "Tesla Service Center",
                    serviceType: "Maintenance",
                    description: "Regular maintenance service",
                    mileageAtService: randomIntBetween(5000, 50000)
                }
            }]
        }
    });
}

// Setup: Generate IDs for linking entities
export function setup() {
    const carIds = [];
    const loanIds = [];
    
    // Generate IDs for 5 events: 2 cars, 1 loan
    carIds.push(`CAR-${Date.now()}-1`);
    carIds.push(`CAR-${Date.now()}-2`);
    loanIds.push(`LOAN-${Date.now()}-1`);
    
    return { carIds, loanIds };
}

// Main test function
export default function (data) {
    const iteration = __ITER; // Current iteration (0-4)
    let payload;
    let eventType;
    
    // Determine which event type based on iteration
    // 0: CarCreated, 1: CarCreated, 2: LoanCreated, 3: LoanPaymentSubmitted, 4: CarServiceDone
    if (iteration === 0 || iteration === 1) {
        // First 2 iterations: CarCreated
        const carIndex = iteration;
        payload = generateCarCreatedEvent(data.carIds[carIndex]);
        eventType = "CarCreated";
    } else if (iteration === 2) {
        // Third iteration: LoanCreated
        payload = generateLoanCreatedEvent(data.carIds[0], data.loanIds[0]);
        eventType = "LoanCreated";
    } else if (iteration === 3) {
        // Fourth iteration: LoanPaymentSubmitted
        payload = generateLoanPaymentEvent(data.loanIds[0]);
        eventType = "LoanPaymentSubmitted";
    } else {
        // Fifth iteration: CarServiceDone
        payload = generateCarServiceEvent(data.carIds[0]);
        eventType = "CarServiceDone";
    }
    
    // Set headers
    const headers = {
        'Content-Type': 'application/json',
    };
    
    const params = {
        headers: headers,
    };
    
    // Send POST request
    const res = http.post(fullApiUrl, payload, params);
    
    // Check response
    const success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 30s': (r) => r.timings.duration < 30000,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('success') || body.includes('processed') || r.status === 200;
        },
    });
    
    errorRate.add(!success);
    eventsSent.add(success);
    
    // Log event type
    console.log(`Sent ${eventType} event (iteration ${iteration + 1}/5)`);
    
    // Small delay between requests
    sleep(0.5);
}

// Summary
export function handleSummary(data) {
    return {
        'stdout': `
========================================
k6 Test Summary - Send 5 Events Total
========================================
Total Iterations: ${data.metrics.iterations.values.count}
Events Sent Successfully: ${data.metrics.events_sent.values.rate * data.metrics.iterations.values.count}
Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
Total Duration: ${(data.metrics.iteration_duration.values.max / 1000).toFixed(2)}s

Event Types Sent:
- CarCreated: 2 events
- LoanCreated: 1 event
- LoanPaymentSubmitted: 1 event
- CarServiceDone: 1 event

API Endpoint: ${fullApiUrl}
========================================
        `,
    };
}
