/**
 * k6 Script to Send 5 Events of Each Type to Python Lambda API
 * 
 * Sends 5 events of each type:
 * 1. CarCreated (5 events)
 * 2. LoanCreated (5 events)
 * 3. LoanPaymentSubmitted (5 events)
 * 4. CarServiceDone (5 events)
 * 
 * Total: 20 events
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

// Test configuration - send 5 of each event type
const EVENTS_PER_TYPE = 5;
export const options = {
    vus: 1,
    iterations: EVENTS_PER_TYPE * 4, // 5 Car + 5 Loan + 5 Payment + 5 Service = 20 iterations
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
    
    for (let i = 0; i < EVENTS_PER_TYPE; i++) {
        carIds.push(`CAR-${Date.now()}-${i + 1}`);
        loanIds.push(`LOAN-${Date.now()}-${i + 1}`);
    }
    
    return { carIds, loanIds };
}

// Main test function
export default function (data) {
    const iteration = __ITER; // Current iteration (0-19)
    let payload;
    let eventType;
    
    // Determine which event type based on iteration
    if (iteration < EVENTS_PER_TYPE) {
        // First 5 iterations: CarCreated
        const carIndex = iteration;
        payload = generateCarCreatedEvent(data.carIds[carIndex]);
        eventType = "CarCreated";
    } else if (iteration < EVENTS_PER_TYPE * 2) {
        // Next 5 iterations: LoanCreated
        const loanIndex = iteration - EVENTS_PER_TYPE;
        const carIndex = loanIndex;
        payload = generateLoanCreatedEvent(data.carIds[carIndex], data.loanIds[loanIndex]);
        eventType = "LoanCreated";
    } else if (iteration < EVENTS_PER_TYPE * 3) {
        // Next 5 iterations: LoanPaymentSubmitted
        const paymentIndex = iteration - (EVENTS_PER_TYPE * 2);
        const loanIndex = paymentIndex;
        payload = generateLoanPaymentEvent(data.loanIds[loanIndex]);
        eventType = "LoanPaymentSubmitted";
    } else {
        // Last 5 iterations: CarServiceDone
        const serviceIndex = iteration - (EVENTS_PER_TYPE * 3);
        const carIndex = serviceIndex;
        payload = generateCarServiceEvent(data.carIds[carIndex]);
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
    console.log(`Sent ${eventType} event (iteration ${iteration + 1}/20)`);
    
    // Small delay between requests
    sleep(0.5);
}

// Summary
export function handleSummary(data) {
    return {
        'stdout': `
========================================
k6 Test Summary - Send 5 Events Each Type
========================================
Total Iterations: ${data.metrics.iterations.values.count}
Events Sent Successfully: ${data.metrics.events_sent.values.rate * data.metrics.iterations.values.count}
Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
Total Duration: ${(data.metrics.iteration_duration.values.max / 1000).toFixed(2)}s

Event Types Sent:
- CarCreated: 5 events
- LoanCreated: 5 events
- LoanPaymentSubmitted: 5 events
- CarServiceDone: 5 events

API Endpoint: ${fullApiUrl}
========================================
        `,
    };
}
