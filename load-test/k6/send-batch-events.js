/**
 * k6 Script to Send Batch Events to REST API (Regular or Lambda)
 * 
 * Sends configurable number of events of each type (always sends all 4 types):
 * 1. Car Created
 * 2. Loan Created
 * 3. Loan Payment Submitted
 * 4. Car Service Done
 * 
 * Flow: k6 → REST API → PostgreSQL/DSQL → CDC → Confluent Cloud
 * 
 * Usage:
 *   # Send 5 events of each type (default, 4 types = 20 total, 1 VU per type = 4 VUs total)
 *   k6 run --env HOST=producer-api-java-rest --env PORT=8081 send-batch-events.js
 * 
 *   # Send 1000 events of each type with 10 VUs per type (4 types = 4000 total, 40 VUs total)
 *   k6 run --env HOST=producer-api-java-rest --env PORT=8081 --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=10 send-batch-events.js
 * 
 *   # Lambda API with PostgreSQL (pg) - 1000 events per type, 20 VUs per type
 *   k6 run --env DB_TYPE=pg --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=20 send-batch-events.js
 * 
 *   # Lambda API with DSQL (dsql) - 1000 events per type, 20 VUs per type
 *   k6 run --env DB_TYPE=dsql --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=20 send-batch-events.js
 * 
 *   # Override API URL explicitly
 *   k6 run --env DB_TYPE=pg --env API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com send-batch-events.js
 * 
 *   # Save events to custom file for validation
 *   k6 run --env DB_TYPE=pg --env EVENTS_FILE=/tmp/my-events.json send-batch-events.js
 *   python3 scripts/validate-against-sent-events.py --events-file /tmp/my-events.json --aurora --dsql
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const eventsSent = new Rate('events_sent');
const carEventsSent = new Rate('car_events_sent');
const loanEventsSent = new Rate('loan_events_sent');
const paymentEventsSent = new Rate('payment_events_sent');
const serviceEventsSent = new Rate('service_events_sent');

// Timing metrics
const requestDuration = new Trend('request_duration', true);
const timeToFirstByte = new Trend('ttfb', true);
const connectionTime = new Trend('connection_time', true);
const dnsTime = new Trend('dns_time', true);
const totalTestDuration = new Trend('total_test_duration', true);

// Per-event-type timing metrics
const carEventDuration = new Trend('car_event_duration', true);
const loanEventDuration = new Trend('loan_event_duration', true);
const paymentEventDuration = new Trend('payment_event_duration', true);
const serviceEventDuration = new Trend('service_event_duration', true);

// Test start time (set in setup)
let testStartTime = null;

// Note: k6 doesn't support shared state between VUs easily
// Events will be collected per-VU and aggregated in handleSummary
// We'll use a workaround: write events to a JSON string that gets appended

// Test configuration - configurable number of events per type via environment variable
// Default: 5 events per type (for quick testing)
// Set EVENTS_PER_TYPE environment variable to override (e.g., --env EVENTS_PER_TYPE=1000)
// Always sends all 4 event types: Car, Loan, Payment, Service
const EVENTS_PER_TYPE = parseInt(__ENV.EVENTS_PER_TYPE || '5', 10);
const NUM_EVENT_TYPES = 4; // Always 4: Car, Loan, Payment, Service

// Parallelism configuration - configurable VUs per event type
// Default: 1 VU per event type (sequential)
// Set VUS_PER_EVENT_TYPE to enable parallelism (e.g., --env VUS_PER_EVENT_TYPE=10)
// Total VUs = VUS_PER_EVENT_TYPE * NUM_EVENT_TYPES
// Each VU handles EVENTS_PER_TYPE / VUS_PER_EVENT_TYPE events of its assigned type
const VUS_PER_EVENT_TYPE = parseInt(__ENV.VUS_PER_EVENT_TYPE || '1', 10);
const TOTAL_VUS = VUS_PER_EVENT_TYPE * NUM_EVENT_TYPES;
const EVENTS_PER_VU = Math.ceil(EVENTS_PER_TYPE / VUS_PER_EVENT_TYPE);

// Sequential processing mode: wait for dependencies to succeed
// Set SEQUENTIAL_MODE=true to enable sequential event processing
// When enabled: Car → Loan → Payment → Service (each waits for previous to complete)
const SEQUENTIAL_MODE = __ENV.SEQUENTIAL_MODE === 'true' || __ENV.SEQUENTIAL_MODE === '1';

export const options = {
    vus: SEQUENTIAL_MODE ? 1 : TOTAL_VUS, // Sequential mode uses 1 VU to process events in order
    iterations: SEQUENTIAL_MODE ? EVENTS_PER_TYPE * NUM_EVENT_TYPES : EVENTS_PER_TYPE * TOTAL_VUS, // Sequential: 5*4=20, Parallel: 5*4*1=20
    maxDuration: '10m',
    thresholds: {
        // Abort if error rate exceeds 50% (half of requests failing)
        'http_req_failed': ['rate<0.5'],
    },
};

// Get API configuration from environment
// Support both regular REST API (HOST/PORT) and Lambda API (API_URL/LAMBDA_API_URL)
// Support DB_TYPE parameter (pg or dsql) to select appropriate Lambda API endpoint
let apiUrl;
const dbType = (__ENV.DB_TYPE || '').toLowerCase();

// If DB_TYPE is specified (pg or dsql), use corresponding Lambda API URL
if (dbType === 'pg' || dbType === 'dsql') {
    // Lambda API - determine URL based on DB_TYPE
    let baseUrl;
    if (__ENV.API_URL) {
        // Explicit API_URL takes precedence
        baseUrl = __ENV.API_URL;
    } else if (dbType === 'pg') {
        // PostgreSQL Lambda API
        baseUrl = __ENV.LAMBDA_PYTHON_REST_API_URL || __ENV.LAMBDA_PG_API_URL || __ENV.LAMBDA_API_URL;
    } else if (dbType === 'dsql') {
        // DSQL Lambda API
        baseUrl = __ENV.LAMBDA_DSQL_API_URL || __ENV.LAMBDA_PYTHON_REST_DSQL_API_URL || __ENV.LAMBDA_API_URL;
    }
    
    if (!baseUrl) {
        throw new Error(`DB_TYPE=${dbType} specified but no API URL found. Please set API_URL, LAMBDA_${dbType.toUpperCase()}_API_URL, or LAMBDA_API_URL environment variable.`);
    }
    
    const apiPath = __ENV.API_PATH || '/api/v1/events';
    apiUrl = baseUrl.includes('/api/v1/events') ? baseUrl : `${baseUrl.replace(/\/$/, '')}${apiPath}`;
} else if (__ENV.API_URL || __ENV.LAMBDA_API_URL || __ENV.LAMBDA_PYTHON_REST_API_URL) {
    // Lambda API - use full URL (legacy support)
    const baseUrl = __ENV.API_URL || __ENV.LAMBDA_API_URL || __ENV.LAMBDA_PYTHON_REST_API_URL;
    const apiPath = __ENV.API_PATH || '/api/v1/events';
    apiUrl = baseUrl.includes('/api/v1/events') ? baseUrl : `${baseUrl.replace(/\/$/, '')}${apiPath}`;
} else if (__ENV.HOST || __ENV.PORT) {
    // Regular REST API - use HOST and PORT if explicitly provided
    const apiHost = __ENV.HOST || 'localhost';
    const apiPort = __ENV.PORT || 8081;
    apiUrl = `http://${apiHost}:${apiPort}/api/v1/events`;
} else {
    // Default to Lambda API (legacy behavior)
    const defaultLambdaUrl = 'https://k5z0vg8boa.execute-api.us-east-1.amazonaws.com';
    const apiPath = __ENV.API_PATH || '/api/v1/events';
    apiUrl = `${defaultLambdaUrl}${apiPath}`;
}

// Authentication configuration
const AUTH_ENABLED = __ENV.AUTH_ENABLED === 'true' || __ENV.AUTH_ENABLED === '1';
const JWT_TOKEN = __ENV.JWT_TOKEN || '';

// Generate unique UUID using VU ID, iteration, timestamp, and random component
// This ensures uniqueness across all VUs and iterations
function generateUUID(vuId = null, iteration = null, eventIndex = null) {
    // Use VU ID and iteration if provided to ensure uniqueness
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 15);
    // Use a counter-based approach instead of performance.now() (not available in k6)
    const counter = (timestamp % 1000000).toString().padStart(6, '0');
    
    // Create a unique seed from VU ID, iteration, and event index
    // This ensures each VU generates unique UUIDs for each event
    let seed = '';
    if (vuId !== null && iteration !== null) {
        // Combine VU ID, iteration, event index, timestamp, counter, and random for maximum uniqueness
        seed = `${vuId}-${iteration}-${eventIndex !== null ? eventIndex : '0'}-${timestamp}-${counter}-${random}`;
    } else {
        // Fallback for schema check (no VU context)
        seed = `${timestamp}-${counter}-${random}`;
    }
    
    // Generate UUID v4 format with deterministic components for uniqueness
    // Use a simple hash-like function to convert seed to hex
    let hex = '';
    for (let i = 0; i < seed.length && hex.length < 32; i++) {
        const charCode = seed.charCodeAt(i);
        hex += charCode.toString(16).padStart(2, '0');
    }
    
    // Pad or truncate to exactly 32 hex characters
    if (hex.length < 32) {
        hex = hex.padEnd(32, '0');
    } else {
        hex = hex.substring(0, 32);
    }
    
    // Format as UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    // Version 4: Set version bits (bits 12-15 of time_hi_and_version to 0100)
    const timeHigh = hex.substring(12, 16);
    const versionedTimeHigh = '4' + timeHigh.substring(1);
    
    // Variant: Set variant bits (bits 6-7 of clock_seq_hi_and_reserved to 10)
    const clockSeq = hex.substring(16, 20);
    const clockSeqFirst = parseInt(clockSeq[0], 16);
    const variantClockSeq = ((clockSeqFirst & 0x3) | 0x8).toString(16) + clockSeq.substring(1);
    
    return [
        hex.substring(0, 8),
        hex.substring(8, 12),
        versionedTimeHigh,
        variantClockSeq,
        hex.substring(20, 32)
    ].join('-');
}

// Generate ISO 8601 timestamp
function generateTimestamp() {
    return new Date().toISOString();
}

// Generate event payloads based on samples
function generateCarCreatedEvent(carId = null, vuId = null, iteration = null, eventIndex = null) {
    const timestamp = generateTimestamp();
    const id = carId || `CAR-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID(vuId, iteration, eventIndex);
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Car Created",
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
            vin: `${randomString(17).toUpperCase()}`,
            make: ["Tesla", "Toyota", "Honda", "Ford", "BMW", "Mercedes", "Audi", "Lexus"][randomIntBetween(0, 7)],
            model: ["Model S", "Camry", "Accord", "F-150", "3 Series", "C-Class", "A4", "ES"][randomIntBetween(0, 7)],
            year: randomIntBetween(2020, 2025),
            color: ["Red", "Blue", "Black", "White", "Silver", "Gray"][randomIntBetween(0, 5)],
            mileage: randomIntBetween(0, 50000),
            lastServiceDate: timestamp,
            totalBalance: (randomIntBetween(0, 50000)).toFixed(2),
            lastLoanPaymentDate: timestamp,
            owner: `${randomString(8)} ${randomString(10)}`
            }
            }]
        }
    });
}

function generateLoanCreatedEvent(carId, loanId = null, vuId = null, iteration = null, eventIndex = null) {
    const timestamp = generateTimestamp();
    const id = loanId || `LOAN-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID(vuId, iteration, eventIndex);
    const loanAmount = randomIntBetween(10000, 100000);
    const interestRate = (2.5 + Math.random() * 5).toFixed(2); // 2.5% - 7.5%
    const termMonths = [24, 36, 48, 60, 72][randomIntBetween(0, 4)];
    const monthlyPayment = (loanAmount * (1 + parseFloat(interestRate) / 100) / termMonths).toFixed(2);
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Loan Created",
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
            financialInstitution: ["First National Bank", "Chase Bank", "Wells Fargo", "Bank of America", "Citibank"][randomIntBetween(0, 4)],
            balance: loanAmount.toFixed(2),
            lastPaidDate: timestamp,
            loanAmount: loanAmount.toFixed(2),
            interestRate: parseFloat(interestRate),
            termMonths: termMonths,
            startDate: timestamp,
            status: "active",
            monthlyPayment: monthlyPayment
            }
            }]
        }
    });
}

function generateLoanPaymentEvent(loanId, amount = null, vuId = null, iteration = null, eventIndex = null) {
    const timestamp = generateTimestamp();
    const paymentId = `PAYMENT-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID(vuId, iteration, eventIndex);
    const paymentAmount = amount || (500 + Math.random() * 1500).toFixed(2); // $500-$2000
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Loan Payment Submitted",
            eventType: "LoanPaymentSubmitted",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
            entityType: "LoanPayment",
            entityId: paymentId,
            updatedAttributes: {
            id: paymentId,
            loanId: loanId,
            amount: parseFloat(paymentAmount).toFixed(2),
            paymentDate: timestamp
            }
            }]
        }
    });
}

function generateCarServiceEvent(carId, serviceId = null, vuId = null, iteration = null, eventIndex = null) {
    const timestamp = generateTimestamp();
    const id = serviceId || `SERVICE-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID(vuId, iteration, eventIndex);
    const amountPaid = (100 + Math.random() * 1000).toFixed(2); // $100-$1100
    const mileageAtService = randomIntBetween(1000, 100000);
    const dealers = [
        "Tesla Service Center - San Francisco",
        "Toyota Service Center - Los Angeles",
        "Honda Service Center - New York",
        "Ford Service Center - Chicago",
        "BMW Service Center - Miami"
    ];
    const dealerId = `DEALER-${randomIntBetween(1, 999)}`;
    const dealerName = dealers[randomIntBetween(0, dealers.length - 1)];
    const descriptions = [
        "Regular maintenance service including tire rotation, brake inspection, and fluid top-up",
        "Oil change and filter replacement",
        "Brake pad replacement and brake fluid flush",
        "Transmission service and fluid change",
        "Battery replacement and electrical system check"
    ];
    const description = descriptions[randomIntBetween(0, descriptions.length - 1)];
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Car Service Done",
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
            amountPaid: parseFloat(amountPaid).toFixed(2),
            dealerId: dealerId,
            dealerName: dealerName,
            mileageAtService: mileageAtService,
            description: description
            }
            }]
        }
    });
}

// File to save sent events for validation
const EVENTS_FILE = __ENV.EVENTS_FILE || '/tmp/k6-sent-events.json';

// Use setup function to generate linked IDs for each batch
export function setup() {
    // Record test start time
    testStartTime = Date.now();
    
    // ============================================================================
    // Database Schema Check
    // ============================================================================
    // Verify that the business_events table exists before running the test
    // This prevents wasting time on a test that will fail due to missing schema
    console.log('Checking database schema...');
    
    // Create a minimal test event to check if the schema exists
    const testEvent = JSON.stringify({
        eventHeader: {
            uuid: generateUUID(),
            eventName: "Car Created",
            eventType: "CarCreated",
            createdDate: generateTimestamp(),
            savedDate: generateTimestamp()
        },
        eventBody: {
            entities: [{
                entityType: "Car",
                entityId: "TEST-SCHEMA-CHECK",
                updatedAttributes: {
                    id: "TEST-SCHEMA-CHECK",
                    vin: "TEST1234567890123",
                    make: "Test",
                    model: "Test Model",
                    year: 2024
                }
            }]
        }
    });
    
    // Prepare headers
    const headers = {
        'Content-Type': 'application/json'
    };
    if (AUTH_ENABLED && JWT_TOKEN) {
        headers['Authorization'] = `Bearer ${JWT_TOKEN}`;
    }
    
    // Make a test request to check if schema exists
    const testResponse = http.post(apiUrl, testEvent, { headers: headers, timeout: '30s' });
    
    // Check response
    if (testResponse.status === 0) {
        // Network/connection error
        console.error(`[SCHEMA CHECK FAILED] Cannot connect to API: ${apiUrl}`);
        console.error(`Error: ${testResponse.error || 'Connection failed'}`);
        throw new Error(`Cannot connect to API: ${apiUrl}. Please check the API URL and network connectivity.`);
    }
    
    const responseBody = testResponse.body || '';
    const responseText = responseBody.toString().toLowerCase();
    
    // Check for database schema errors - be very explicit about error patterns
    const hasSchemaError = (
        (responseText.includes('relation') && responseText.includes('does not exist')) ||
        (responseText.includes('business_events') && responseText.includes('not exist')) ||
        (responseText.includes('relation') && responseText.includes('business_events') && responseText.includes('does not exist')) ||
        responseText.includes('relation "business_events" does not exist') ||
        responseText.includes("relation 'business_events' does not exist")
    );
    
    // If we get a 500 error AND it's a schema error, abort
    if (testResponse.status >= 500 && hasSchemaError) {
        console.error('='.repeat(70));
        console.error('[SCHEMA CHECK FAILED] Database schema is missing!');
        console.error('='.repeat(70));
        console.error(`API URL: ${apiUrl}`);
        console.error(`Response Status: ${testResponse.status}`);
        console.error(`Response Body: ${responseBody}`);
        console.error('');
        console.error('ERROR: The business_events table does not exist in the database.');
        console.error('');
        console.error('SOLUTION: Initialize the database schema before running tests:');
        console.error('  cd /Users/rickzakharov/dev/github/api-performance-multi-lang');
        console.error('  python3 scripts/init-aurora-schema.py');
        console.error('');
        console.error('Or run: terraform apply (if using Terraform-managed infrastructure)');
        console.error('='.repeat(70));
        
        throw new Error('Database schema check failed: business_events table does not exist. Please initialize the schema before running tests.');
    }
    
    // If we get a 500 error but it's not a schema error, still warn but don't abort
    if (testResponse.status >= 500 && !hasSchemaError) {
        console.warn(`⚠ Warning: API returned ${testResponse.status} but error doesn't appear to be schema-related`);
        console.warn(`Response: ${responseBody}`);
    }
    
    // If we get a 200/201, schema exists and test event was created
    if (testResponse.status === 200 || testResponse.status === 201) {
        console.log('✓ Database schema check passed (test event created successfully)');
    } else if (testResponse.status === 400) {
        // 400 might be validation error, but schema exists
        console.log('✓ Database schema check passed (API responded, schema exists)');
    } else if (testResponse.status < 500) {
        // Any 2xx or 4xx (except 500+) means API is working, schema likely exists
        console.log(`✓ Database schema check passed (API responded with status ${testResponse.status})`);
    }
    console.log('');
    
    // ============================================================================
    // Generate Test Data
    // ============================================================================
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carIds = [];
    const loanIds = [];
    const monthlyPayments = [];
    const serviceIds = [];
    
    // Generate linked IDs for all events
    for (let i = 0; i < EVENTS_PER_TYPE; i++) {
        carIds.push(`CAR-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        loanIds.push(`LOAN-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        monthlyPayments.push((500 + Math.random() * 1500).toFixed(2));
        serviceIds.push(`SERVICE-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
    }
    
    return {
        carIds: carIds,
        loanIds: loanIds,
        monthlyPayments: monthlyPayments,
        serviceIds: serviceIds,
        successfulCars: {}, // Track successful Car creations for sequential mode
        successfulLoans: {}, // Track successful Loan creations for sequential mode
        sentEvents: [] // Collect sent events for validation (per-VU)
    };
}

export default function (data) {
    const vuId = __VU; // Virtual User ID (1 to TOTAL_VUS)
    const globalIteration = __ITER; // Global iteration (0 to TOTAL_ITERATIONS-1)
    let payload;
    let eventType;
    let success;
    let eventIndexInType; // Event index within the event type (0 to EVENTS_PER_TYPE-1)
    
    // Sequential mode: process events in order (Car → Loan → Payment → Service)
    // Each event type waits for previous to complete before starting
    if (SEQUENTIAL_MODE) {
        // In sequential mode, iterations are: 0-4: Car, 5-9: Loan, 10-14: Payment, 15-19: Service
        const eventTypeIndex = Math.floor(globalIteration / EVENTS_PER_TYPE);
        eventIndexInType = globalIteration - (eventTypeIndex * EVENTS_PER_TYPE);
        
        // Ensure we don't exceed the number of event types
        if (eventTypeIndex >= NUM_EVENT_TYPES) {
            return; // This iteration is beyond our event types
        }
        
        // For Payment and Service events, check if dependencies succeeded
        if (eventTypeIndex === 2) {
            // Loan Payment: check if corresponding Loan was created successfully
            // We'll track this in shared data
            if (!data.successfulLoans || !data.successfulLoans[eventIndexInType]) {
                console.log(`[VU ${vuId}] Skipping Loan Payment ${eventIndexInType + 1}/${EVENTS_PER_TYPE}: Loan ${eventIndexInType} not created yet`);
                // Still try to send, but log the dependency issue
            }
        } else if (eventTypeIndex === 3) {
            // Car Service: check if corresponding Car was created successfully
            if (!data.successfulCars || !data.successfulCars[eventIndexInType]) {
                console.log(`[VU ${vuId}] Skipping Car Service ${eventIndexInType + 1}/${EVENTS_PER_TYPE}: Car ${eventIndexInType} not created yet`);
                // Still try to send, but log the dependency issue
            }
        }
    } else {
        // Parallel mode: original logic
        // Determine which event type this iteration should send based on global iteration
        // Iterations 0-9: Car, 10-19: Loan, 20-29: Payment, 30-39: Service
        const eventTypeIndex = Math.floor(globalIteration / EVENTS_PER_TYPE);
        
        // Ensure we don't exceed the number of event types
        if (eventTypeIndex >= NUM_EVENT_TYPES) {
            return; // This iteration is beyond our event types
        }
        
        // Calculate the event index within the event type (0 to EVENTS_PER_TYPE-1)
        // For Car (iterations 0-9): eventIndexInType = 0-9
        // For Loan (iterations 10-19): eventIndexInType = 0-9
        // etc.
        eventIndexInType = globalIteration - (eventTypeIndex * EVENTS_PER_TYPE);
    }
    
    // Determine event type index for payload generation
    const eventTypeIndex = SEQUENTIAL_MODE 
        ? Math.floor(globalIteration / EVENTS_PER_TYPE)
        : Math.floor(globalIteration / EVENTS_PER_TYPE);
    
    // Determine which VU should handle this event type
    // VU assignment: VU 1-VUS_PER_EVENT_TYPE handle Car, 
    //                VU VUS_PER_EVENT_TYPE+1 to 2*VUS_PER_EVENT_TYPE handle Loan, etc.
    const expectedVuStart = eventTypeIndex * VUS_PER_EVENT_TYPE + 1;
    const expectedVuEnd = (eventTypeIndex + 1) * VUS_PER_EVENT_TYPE;
    
    // Check if this VU should handle this event type
    // Since k6 distributes iterations non-deterministically, we allow any VU to process
    // any iteration, but we ensure each iteration sends the correct event type
    // This way, all 40 iterations will send events, regardless of which VU processes them
    
    // Generate the appropriate event based on event type
    // Pass VU ID, globalIteration, and event index to ensure unique UUIDs
    if (eventTypeIndex === 0) {
        // Car Created
        payload = generateCarCreatedEvent(data.carIds[eventIndexInType], vuId, globalIteration, eventIndexInType);
        eventType = "CarCreated";
    } else if (eventTypeIndex === 1) {
        // Loan Created
        const carIndex = eventIndexInType; // Link to corresponding car
        payload = generateLoanCreatedEvent(data.carIds[carIndex], data.loanIds[eventIndexInType], vuId, globalIteration, eventIndexInType);
        eventType = "LoanCreated";
    } else if (eventTypeIndex === 2) {
        // Loan Payment Submitted
        const loanIndex = eventIndexInType; // Link to corresponding loan
        payload = generateLoanPaymentEvent(data.loanIds[loanIndex], data.monthlyPayments[eventIndexInType], vuId, globalIteration, eventIndexInType);
        eventType = "LoanPaymentSubmitted";
    } else {
        // Car Service Done
        const carIndex = eventIndexInType; // Link to corresponding car
        payload = generateCarServiceEvent(data.carIds[carIndex], data.serviceIds[eventIndexInType], vuId, globalIteration, eventIndexInType);
        eventType = "CarServiceDone";
    }
    
    // Set headers
    const headers = {
        'Content-Type': 'application/json',
    };
    
    // Add Authorization header if auth is enabled
    if (AUTH_ENABLED && JWT_TOKEN) {
        headers['Authorization'] = `Bearer ${JWT_TOKEN}`;
    }
    
    const params = {
        headers: headers,
    };
    
    // Record request start time for timing metrics
    const requestStartTime = Date.now();
    
    // Send POST request
    const res = http.post(apiUrl, payload, params);
    
    // Record request end time and calculate durations
    const requestEndTime = Date.now();
    const requestDurationMs = requestEndTime - requestStartTime;
    
    // Extract timing metrics from response
    const timings = res.timings || {};
    const duration = timings.duration || requestDurationMs;
    const ttfb = timings.time_to_first_byte || (timings.waiting || 0);
    const connection = timings.connecting || 0;
    const dns = timings.dns_lookup || 0;
    
    // Record timing metrics
    requestDuration.add(duration);
    timeToFirstByte.add(ttfb);
    connectionTime.add(connection);
    dnsTime.add(dns);
    
    // Record per-event-type timing
    if (eventType === "CarCreated") {
        carEventDuration.add(duration);
    } else if (eventType === "LoanCreated") {
        loanEventDuration.add(duration);
    } else if (eventType === "LoanPaymentSubmitted") {
        paymentEventDuration.add(duration);
    } else if (eventType === "CarServiceDone") {
        serviceEventDuration.add(duration);
    }
    
    // Use iterationWithinEventType for logging (defined earlier in function)
    
    // Check response (use longer timeout for Lambda APIs)
    const isLambda = apiUrl.includes('execute-api') || apiUrl.includes('amazonaws.com');
    const timeout = isLambda ? 30000 : 5000; // 30s for Lambda, 5s for regular API
    
    // Check if request was successful (status 200)
    const isSuccess = res.status === 200;
    
    success = check(res, {
        'status is 200': (r) => r.status === 200,
        [`response time < ${timeout}ms`]: (r) => r.timings.duration < timeout,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('successfully') || body.includes('processed') || body.includes('Event processed') || body.includes('"success":true') || r.status === 200;
        },
    });
    
    // Track successful events for sequential mode dependencies
    if (SEQUENTIAL_MODE && success && res.status === 200) {
        if (eventType === "CarCreated") {
            if (!data.successfulCars) data.successfulCars = {};
            data.successfulCars[eventIndexInType] = true;
        } else if (eventType === "LoanCreated") {
            if (!data.successfulLoans) data.successfulLoans = {};
            data.successfulLoans[eventIndexInType] = true;
        }
    }
    
    // Check for schema errors in response and abort immediately
    const responseBody = res.body || '';
    const responseText = responseBody.toString().toLowerCase();
    const isSchemaError = (
        res.status >= 500 && (
            (responseText.includes('relation') && responseText.includes('does not exist')) ||
            (responseText.includes('business_events') && responseText.includes('not exist')) ||
            (responseText.includes('relation') && responseText.includes('business_events') && responseText.includes('does not exist')) ||
            responseText.includes('relation "business_events" does not exist') ||
            responseText.includes("relation 'business_events' does not exist")
        )
    );
    
    // Abort immediately if schema error detected (prevents wasting resources)
    if (isSchemaError) {
        console.error('='.repeat(70));
        console.error(`[VU ${vuId} ABORTED] Database schema error detected!`);
        console.error('='.repeat(70));
        console.error(`Event Type: ${eventType}`);
        console.error(`Event Index: ${eventIndexInType}`);
        console.error(`Response Status: ${res.status}`);
        console.error(`Response Body: ${responseBody.substring(0, 500)}`);
        console.error('');
        console.error('ERROR: The business_events table does not exist in the database.');
        console.error('');
        console.error('SOLUTION: Initialize the database schema before running tests:');
        console.error('  cd /Users/rickzakharov/dev/github/api-performance-multi-lang');
        console.error('  python3 scripts/init-aurora-schema.py');
        console.error('');
        console.error('Or run: terraform apply (if using Terraform-managed infrastructure)');
        console.error('='.repeat(70));
        
        // Abort this VU's execution
        throw new Error('Database schema is missing. Test aborted. Please initialize the schema before running tests.');
    }
    
    // Log errors immediately for visibility
    if (!success || res.status !== 200) {
        const errorMsg = res.status >= 400 ? `HTTP ${res.status}: ${res.body?.substring(0, 200) || 'No response body'}` : 'Request failed checks';
        console.error(`[ERROR] [VU ${vuId}] ${eventType} event failed (event ${eventIndexInType + 1}/${EVENTS_PER_TYPE}, global iteration ${globalIteration}): ${errorMsg}`);
        
        // Log first few errors in detail, then summarize
        if (eventIndexInType < 5) {
            console.error(`  Full response: ${JSON.stringify(res.body).substring(0, 500)}`);
        }
    }
    
    errorRate.add(!success);
    eventsSent.add(success);
    
    // Track by event type
    if (eventType === "CarCreated") {
        carEventsSent.add(success);
    } else if (eventType === "LoanCreated") {
        loanEventsSent.add(success);
    } else if (eventType === "LoanPaymentSubmitted") {
        paymentEventsSent.add(success);
    } else if (eventType === "CarServiceDone") {
        serviceEventsSent.add(success);
    }
    
    // Save successful events to data object for validation
    // Save if status is 200 (regardless of check() result, as check() may fail on timing)
    if (res.status === 200) {
        try {
            const eventData = JSON.parse(payload);
            const savedEvent = {
                uuid: eventData.eventHeader.uuid,
                eventName: eventData.eventHeader.eventName,
                eventType: eventData.eventHeader.eventType,
                entityType: eventData.eventBody.entities[0]?.entityType,
                entityId: eventData.eventBody.entities[0]?.entityId,
                timestamp: new Date().toISOString(),
                vuId: vuId,
                iteration: globalIteration,
                eventIndex: eventIndexInType
            };
            
            // Add to data object (per-VU, will be aggregated in handleSummary)
            if (!data.sentEvents) {
                data.sentEvents = [];
            }
            data.sentEvents.push(savedEvent);
            
            // Also log event in a parseable format for collection
            // Format: K6_EVENT: <json>
            console.log(`K6_EVENT: ${JSON.stringify(savedEvent)}`);
        } catch (e) {
            // Silently fail - event saving is optional
        }
    }
    
    // Log progress periodically (every 10% or every 100 events, whichever is smaller)
    const logInterval = Math.max(1, Math.min(Math.floor(EVENTS_PER_TYPE / 10), 100));
    if (eventIndexInType % logInterval === 0 || eventIndexInType === EVENTS_PER_TYPE - 1) {
        console.log(`[VU ${vuId}] Sent ${eventType} event (${eventIndexInType + 1}/${EVENTS_PER_TYPE} for this type, global iteration ${globalIteration})`);
    }
    
    // Small delay between events
    sleep(0.1);
}

export function teardown(data) {
    // Record total test duration
    if (testStartTime) {
        const totalDuration = Date.now() - testStartTime;
        totalTestDuration.add(totalDuration);
    }
}

export function handleSummary(data) {
    return generateSummaryText(data);
}

function generateSummaryText(data) {
    // Safely access metrics with fallbacks
    const totalRequests = data.metrics?.http_reqs?.values?.count || 0;
    const totalErrors = data.metrics?.errors?.values?.count || 0;
    const errorRate = totalRequests > 0 ? ((totalErrors / totalRequests) * 100).toFixed(2) : 0;
    
    // Rate metrics use 'passes' for successful events (when add(true) was called)
    const carSent = data.metrics?.car_events_sent?.values?.passes || 0;
    const loanSent = data.metrics?.loan_events_sent?.values?.passes || 0;
    const paymentSent = data.metrics?.payment_events_sent?.values?.passes || 0;
    const serviceSent = data.metrics?.service_events_sent?.values?.passes || 0;
    
    // Overall HTTP metrics
    const rate = data.metrics?.http_req_duration?.values?.rate || 0;
    const avg = data.metrics?.http_req_duration?.values?.avg || 0;
    const min = data.metrics?.http_req_duration?.values?.min || 0;
    const max = data.metrics?.http_req_duration?.values?.max || 0;
    const p95 = data.metrics?.http_req_duration?.values?.['p(95)'] || 0;
    const p99 = data.metrics?.http_req_duration?.values?.['p(99)'] || 0;
    
    // Custom timing metrics
    const reqDurationAvg = data.metrics.request_duration?.values?.avg || avg;
    const reqDurationMin = data.metrics.request_duration?.values?.min || min;
    const reqDurationMax = data.metrics.request_duration?.values?.max || max;
    const reqDurationP95 = data.metrics.request_duration?.values?.['p(95)'] || p95;
    const reqDurationP99 = data.metrics.request_duration?.values?.['p(99)'] || p99;
    
    const ttfbAvg = data.metrics.ttfb?.values?.avg || 0;
    const ttfbP95 = data.metrics.ttfb?.values?.['p(95)'] || 0;
    const ttfbP99 = data.metrics.ttfb?.values?.['p(99)'] || 0;
    
    const connAvg = data.metrics.connection_time?.values?.avg || 0;
    const dnsAvg = data.metrics.dns_time?.values?.avg || 0;
    
    // Per-event-type timing
    const carAvg = data.metrics.car_event_duration?.values?.avg || 0;
    const carP95 = data.metrics.car_event_duration?.values?.['p(95)'] || 0;
    const loanAvg = data.metrics.loan_event_duration?.values?.avg || 0;
    const loanP95 = data.metrics.loan_event_duration?.values?.['p(95)'] || 0;
    const paymentAvg = data.metrics.payment_event_duration?.values?.avg || 0;
    const paymentP95 = data.metrics.payment_event_duration?.values?.['p(95)'] || 0;
    const serviceAvg = data.metrics.service_event_duration?.values?.avg || 0;
    const serviceP95 = data.metrics.service_event_duration?.values?.['p(95)'] || 0;
    
    // Test duration
    const testDuration = data.state.testRunDurationMs || 0;
    const testDurationSec = (testDuration / 1000).toFixed(2);
    
    // Build event summary string
    const eventsSummary = `${EVENTS_PER_TYPE} Car Created + ${EVENTS_PER_TYPE} Loan Created + ${EVENTS_PER_TYPE} Loan Payment Submitted + ${EVENTS_PER_TYPE} Car Service Done`;
    
    const eventsByType = `  Car Created: ${carSent}/${EVENTS_PER_TYPE}
    Loan Created: ${loanSent}/${EVENTS_PER_TYPE}
    Loan Payment Submitted: ${paymentSent}/${EVENTS_PER_TYPE}
    Car Service Done: ${serviceSent}/${EVENTS_PER_TYPE}`;
    
    // Determine DB type for summary
    const dbTypeDisplay = dbType ? ` (${dbType.toUpperCase()})` : '';
    const modeDisplay = SEQUENTIAL_MODE ? ' (Sequential Mode)' : ' (Parallel Mode)';
    
    return {
        'stdout': `
    ========================================
    k6 Batch Events Test Summary
    ========================================

    API Endpoint: ${apiUrl}${dbTypeDisplay}${modeDisplay}
    Events Sent: ${eventsSummary}
    Total Events: ${EVENTS_PER_TYPE * NUM_EVENT_TYPES}
    Event Types: ${NUM_EVENT_TYPES}
    Parallelism: ${VUS_PER_EVENT_TYPE} VUs per event type (${TOTAL_VUS} total VUs)
    Events per VU: ${EVENTS_PER_VU} per event type
    Test Duration: ${testDurationSec}s
    ========================================

HTTP Requests:
  Total: ${totalRequests}
  Rate: ${rate.toFixed(2)} req/s
  Error Rate: ${errorRate}%
  Errors: ${totalErrors}

Overall Response Time:
  Avg: ${avg.toFixed(2)}ms
  Min: ${min.toFixed(2)}ms
  Max: ${max.toFixed(2)}ms
  P95: ${p95.toFixed(2)}ms
  P99: ${p99.toFixed(2)}ms

Detailed Timing Metrics:
  Request Duration:
    Avg: ${reqDurationAvg.toFixed(2)}ms
    Min: ${reqDurationMin.toFixed(2)}ms
    Max: ${reqDurationMax.toFixed(2)}ms
    P95: ${reqDurationP95.toFixed(2)}ms
    P99: ${reqDurationP99.toFixed(2)}ms
  Time to First Byte (TTFB):
    Avg: ${ttfbAvg.toFixed(2)}ms
    P95: ${ttfbP95.toFixed(2)}ms
    P99: ${ttfbP99.toFixed(2)}ms
  Connection Time:
    Avg: ${connAvg.toFixed(2)}ms
  DNS Lookup Time:
    Avg: ${dnsAvg.toFixed(2)}ms

Per-Event-Type Timing (Avg / P95):
  Car Created: ${carAvg.toFixed(2)}ms / ${carP95.toFixed(2)}ms
  Loan Created: ${loanAvg.toFixed(2)}ms / ${loanP95.toFixed(2)}ms
  Loan Payment: ${paymentAvg.toFixed(2)}ms / ${paymentP95.toFixed(2)}ms
  Car Service: ${serviceAvg.toFixed(2)}ms / ${serviceP95.toFixed(2)}ms

Events by Type:
${eventsByType}

Next Steps:
  1. Verify events in PostgreSQL database
  2. Check Confluent CDC connector status
  3. Verify events in Confluent Cloud input topics
  4. Check Flink jobs/SQL statements
  5. Verify events in Confluent Cloud output topics
`
    };
}
