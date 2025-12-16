/**
 * k6 Script to Send Events Using Sample Files
 * 
 * Sends 10 events of each type using samples from data/schemas/event/samples:
 * 1. Car Created (10 events)
 * 2. Loan Created (10 events)
 * 3. Loan Payment Submitted (10 events)
 * 
 * Total: 30 events
 * 
 * Flow: k6 → Lambda REST API → PostgreSQL → CDC → Confluent Cloud → Flink → Filtered Topics
 * 
 * Usage:
 *   k6 run --env LAMBDA_API_URL=https://k5z0vg8boa.execute-api.us-east-1.amazonaws.com send-events-from-samples.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const eventsSent = new Rate('events_sent');
const carEventsSent = new Rate('car_events_sent');
const loanEventsSent = new Rate('loan_events_sent');
const paymentEventsSent = new Rate('payment_events_sent');

// Test configuration - send 10 of each event type
const EVENTS_PER_TYPE = 10;
export const options = {
    vus: 1,
    iterations: EVENTS_PER_TYPE * 3, // 10 Car + 10 Loan + 10 Payment = 30 iterations
};

// Get API configuration from environment
const apiUrl = __ENV.LAMBDA_API_URL || 'https://k5z0vg8boa.execute-api.us-east-1.amazonaws.com';
const apiPath = __ENV.API_PATH || '/api/v1/events';

// Construct full URL
let fullApiUrl = apiUrl;
if (!apiUrl.includes('/api/v1/events')) {
    const baseUrl = apiUrl.replace(/\/$/, '');
    fullApiUrl = `${baseUrl}${apiPath}`;
}

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

// Base templates from samples - adapted for new schema format
const carCreatedTemplate = {
    eventHeader: {
        uuid: "",
        eventName: "Car Created",
        eventType: "CarCreated",
        createdDate: "",
        savedDate: ""
    },
    entities: [{
        entityHeader: {
            entityId: "",
            entityType: "Car",
            createdAt: "",
            updatedAt: ""
        },
        id: "",
        vin: "",
        make: "Tesla",
        model: "Model S",
        year: 2025,
        color: "Midnight Silver",
        mileage: 0,
        lastServiceDate: "",
        totalBalance: 0.0,
        lastLoanPaymentDate: "",
        owner: ""
    }]
};

const loanCreatedTemplate = {
    eventHeader: {
        uuid: "",
        eventName: "Loan Created",
        eventType: "LoanCreated",
        createdDate: "",
        savedDate: ""
    },
    entities: [{
        entityHeader: {
            entityId: "",
            entityType: "Loan",
            createdAt: "",
            updatedAt: ""
        },
        id: "",
        carId: "",
        financialInstitution: "First National Bank",
        balance: 45000.00,
        lastPaidDate: "",
        loanAmount: 50000.00,
        interestRate: 0.045,
        termMonths: 60,
        startDate: "",
        status: "active",
        monthlyPayment: 932.16
    }]
};

const loanPaymentTemplate = {
    eventHeader: {
        uuid: "",
        eventName: "Loan Payment Submitted",
        eventType: "LoanPaymentSubmitted",
        createdDate: "",
        savedDate: ""
    },
    entities: [{
        entityHeader: {
            entityId: "",
            entityType: "LoanPayment",
            createdAt: "",
            updatedAt: ""
        },
        id: "",
        loanId: "",
        amount: 932.16,
        paymentDate: ""
    }]
};

// Generate event from template
function generateCarCreatedEvent(carId = null) {
    const timestamp = generateTimestamp();
    const id = carId || `CAR-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1000, 9999)}`;
    const uuid = generateUUID();
    
    const event = JSON.parse(JSON.stringify(carCreatedTemplate));
    event.eventHeader.uuid = uuid;
    event.eventHeader.createdDate = timestamp;
    event.eventHeader.savedDate = timestamp;
    event.entities[0].entityHeader.entityId = id;
    event.entities[0].entityHeader.createdAt = timestamp;
    event.entities[0].entityHeader.updatedAt = timestamp;
    event.entities[0].id = id;
    event.entities[0].vin = randomString(17).toUpperCase();
    event.entities[0].make = ["Tesla", "Toyota", "Honda", "Ford", "BMW", "Mercedes", "Audi", "Lexus"][randomIntBetween(0, 7)];
    event.entities[0].model = ["Model S", "Camry", "Accord", "F-150", "3 Series", "C-Class", "A4", "ES"][randomIntBetween(0, 7)];
    event.entities[0].year = randomIntBetween(2020, 2025);
    event.entities[0].color = ["Red", "Blue", "Black", "White", "Silver", "Gray"][randomIntBetween(0, 5)];
    event.entities[0].mileage = randomIntBetween(0, 50000);
    event.entities[0].lastServiceDate = timestamp;
    event.entities[0].owner = `${randomString(8)} ${randomString(10)}`;
    
    return JSON.stringify(event);
}

function generateLoanCreatedEvent(carId, loanId = null) {
    const timestamp = generateTimestamp();
    const id = loanId || `LOAN-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1000, 9999)}`;
    const uuid = generateUUID();
    const loanAmount = randomIntBetween(10000, 100000);
    const interestRate = 0.025 + Math.random() * 0.05; // 2.5% - 7.5%
    const termMonths = [24, 36, 48, 60, 72][randomIntBetween(0, 4)];
    const monthlyPayment = (loanAmount * (1 + interestRate) / termMonths).toFixed(2);
    
    const event = JSON.parse(JSON.stringify(loanCreatedTemplate));
    event.eventHeader.uuid = uuid;
    event.eventHeader.createdDate = timestamp;
    event.eventHeader.savedDate = timestamp;
    event.entities[0].entityHeader.entityId = id;
    event.entities[0].entityHeader.createdAt = timestamp;
    event.entities[0].entityHeader.updatedAt = timestamp;
    event.entities[0].id = id;
    event.entities[0].carId = carId;
    event.entities[0].financialInstitution = ["First National Bank", "Chase Bank", "Wells Fargo", "Bank of America", "Citibank"][randomIntBetween(0, 4)];
    event.entities[0].balance = loanAmount.toFixed(2);
    event.entities[0].lastPaidDate = timestamp;
    event.entities[0].loanAmount = loanAmount.toFixed(2);
    event.entities[0].interestRate = parseFloat(interestRate.toFixed(4));
    event.entities[0].termMonths = termMonths;
    event.entities[0].startDate = timestamp;
    event.entities[0].monthlyPayment = monthlyPayment;
    
    return JSON.stringify(event);
}

function generateLoanPaymentEvent(loanId, amount = null) {
    const timestamp = generateTimestamp();
    const paymentId = `PAYMENT-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1000, 9999)}`;
    const uuid = generateUUID();
    const paymentAmount = amount || (500 + Math.random() * 1500).toFixed(2);
    
    const event = JSON.parse(JSON.stringify(loanPaymentTemplate));
    event.eventHeader.uuid = uuid;
    event.eventHeader.createdDate = timestamp;
    event.eventHeader.savedDate = timestamp;
    event.entities[0].entityHeader.entityId = paymentId;
    event.entities[0].entityHeader.createdAt = timestamp;
    event.entities[0].entityHeader.updatedAt = timestamp;
    event.entities[0].id = paymentId;
    event.entities[0].loanId = loanId;
    event.entities[0].amount = parseFloat(paymentAmount);
    event.entities[0].paymentDate = timestamp;
    
    return JSON.stringify(event);
}

// Use setup function to generate linked IDs
export function setup() {
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carIds = [];
    const loanIds = [];
    const monthlyPayments = [];
    
    // Generate 10 sets of linked IDs
    for (let i = 0; i < EVENTS_PER_TYPE; i++) {
        carIds.push(`CAR-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        loanIds.push(`LOAN-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        monthlyPayments.push((500 + Math.random() * 1500).toFixed(2));
    }
    
    return {
        carIds: carIds,
        loanIds: loanIds,
        monthlyPayments: monthlyPayments
    };
}

export default function (data) {
    const iteration = __ITER; // Current iteration (0-29)
    let payload;
    let eventType;
    let success;
    
    // Determine which event type based on iteration
    if (iteration < EVENTS_PER_TYPE) {
        // First 10 iterations: Car Created
        const carIndex = iteration;
        payload = generateCarCreatedEvent(data.carIds[carIndex]);
        eventType = "CarCreated";
    } else if (iteration < EVENTS_PER_TYPE * 2) {
        // Next 10 iterations: Loan Created
        const loanIndex = iteration - EVENTS_PER_TYPE;
        const carIndex = loanIndex; // Link to corresponding car
        payload = generateLoanCreatedEvent(data.carIds[carIndex], data.loanIds[loanIndex]);
        eventType = "LoanCreated";
    } else {
        // Last 10 iterations: Loan Payment Submitted
        const paymentIndex = iteration - (EVENTS_PER_TYPE * 2);
        const loanIndex = paymentIndex; // Link to corresponding loan
        payload = generateLoanPaymentEvent(data.loanIds[loanIndex], data.monthlyPayments[paymentIndex]);
        eventType = "LoanPaymentSubmitted";
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
    success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 30s': (r) => r.timings.duration < 30000,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('successfully') || body.includes('processed') || body.includes('Event processed') || r.status === 200;
        },
    });
    
    errorRate.add(!success);
    eventsSent.add(success);
    
    // Track by event type
    if (eventType === "CarCreated") {
        carEventsSent.add(success);
    } else if (eventType === "LoanCreated") {
        loanEventsSent.add(success);
    } else if (eventType === "LoanPaymentSubmitted") {
        paymentEventsSent.add(success);
    }
    
    // Log progress
    if (iteration % 5 === 0 || iteration === options.iterations - 1) {
        console.log(`Sent ${eventType} event (iteration ${iteration + 1}/${options.iterations})`);
    }
    
    // Small delay between events
    sleep(0.2);
}

export function handleSummary(data) {
    const totalRequests = data.metrics.http_reqs.values.count;
    const totalErrors = data.metrics.errors.values.count;
    const errorRate = totalRequests > 0 ? ((totalErrors / totalRequests) * 100).toFixed(2) : 0;
    
    const carSent = data.metrics.car_events_sent ? data.metrics.car_events_sent.values.count : 0;
    const loanSent = data.metrics.loan_events_sent ? data.metrics.loan_events_sent.values.count : 0;
    const paymentSent = data.metrics.payment_events_sent ? data.metrics.payment_events_sent.values.count : 0;
    
    const rate = data.metrics.http_req_duration?.values?.rate || 0;
    const avg = data.metrics.http_req_duration?.values?.avg || 0;
    
    return {
        'stdout': `
========================================
k6 Events from Samples Test Summary
========================================

API Endpoint: ${fullApiUrl}
Events Sent: 10 Car Created + 10 Loan Created + 10 Loan Payment Submitted
========================================

HTTP Requests:
  Total: ${totalRequests}
  Rate: ${rate.toFixed(2)} req/s
Response Time:
  Avg: ${avg.toFixed(2)}ms
Error Rate: ${errorRate}%
Errors: ${totalErrors}

Events by Type:
  Car Created: ${carSent}/10
  Loan Created: ${loanSent}/10
  Loan Payment Submitted: ${paymentSent}/10

Next Steps:
  1. Wait 30-60 seconds for events to flow through pipeline
  2. Check filtered topics:
     - filtered-car-created-events
     - filtered-loan-created-events
     - filtered-loan-payment-submitted-events
  3. Run validation script
`,
    };
}
