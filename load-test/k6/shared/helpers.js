/**
 * Shared helper functions for k6 test scripts
 */

import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

/**
 * Generate a random UUID-like string
 */
export function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

/**
 * Generate ISO 8601 timestamp
 */
export function generateTimestamp() {
    return new Date().toISOString();
}

/**
 * Parse payload size from environment variable or string
 * Supports: '4k', '8k', '32k', '64k' or number in bytes
 * Returns size in bytes, or null if invalid
 */
export function parsePayloadSize(sizeStr) {
    if (!sizeStr) {
        return null; // Default to small payload
    }
    
    const str = sizeStr.toString().toLowerCase().trim();
    
    // Handle 'k' suffix (kilobytes)
    if (str.endsWith('k')) {
        const num = parseInt(str.slice(0, -1), 10);
        if (!isNaN(num) && num > 0) {
            return num * 1024;
        }
    }
    
    // Handle plain number (bytes)
    const num = parseInt(str, 10);
    if (!isNaN(num) && num > 0) {
        return num;
    }
    
    return null;
}

/**
 * Get target payload size from environment variable
 * Returns size in bytes or null for default small payload
 */
export function getTargetPayloadSize() {
    const payloadSize = __ENV.PAYLOAD_SIZE;
    return parsePayloadSize(payloadSize);
}

/**
 * Convert nested objects to string values for gRPC (map<string, string>)
 */
function stringifyAttributesForGrpc(attributes) {
    const result = {};
    for (const [key, value] of Object.entries(attributes)) {
        if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
            // Convert nested objects to JSON strings
            result[key] = JSON.stringify(value);
        } else if (Array.isArray(value)) {
            // Convert arrays to JSON strings
            result[key] = JSON.stringify(value);
        } else {
            // Keep primitive values as strings
            result[key] = String(value);
        }
    }
    return result;
}

/**
 * Expand updatedAttributes to reach target size
 * Adds realistic nested structures and padding
 */
function expandAttributesToSize(updatedAttributes, targetSizeBytes) {
    if (!targetSizeBytes) {
        return updatedAttributes; // Return as-is for default small payload
    }
    
    // Create a copy to avoid modifying original
    const expanded = JSON.parse(JSON.stringify(updatedAttributes));
    
    // Add nested structures based on entity type
    if (expanded.id && expanded.id.includes('car')) {
        // Add car-specific nested data
        expanded.owner = {
            id: `OWNER-${randomString(8)}`,
            firstName: randomString(8),
            lastName: randomString(10),
            email: `${randomString(10)}@example.com`,
            phone: `+1-555-${randomString(7)}`,
            address: {
                street: `${randomIntBetween(1, 9999)} ${randomString(10)} Street`,
                city: randomString(12),
                state: randomString(2).toUpperCase(),
                zipCode: randomString(5),
                country: 'USA'
            }
        };
        
        expanded.insurance = {
            provider: randomString(12),
            policyNumber: `POL-${randomString(10)}`,
            expiryDate: generateTimestamp(),
            coverageType: 'Full Coverage',
            premiumAmount: randomIntBetween(500, 2000),
            deductible: randomIntBetween(250, 1000)
        };
        
        expanded.maintenance = {
            lastServiceDate: generateTimestamp(),
            nextServiceDue: generateTimestamp(),
            mileage: randomIntBetween(0, 100000),
            oilChangeInterval: randomIntBetween(5000, 15000),
            tireRotationInterval: randomIntBetween(5000, 10000),
            warrantyCoverage: 'Active',
            warrantyExpiryDate: generateTimestamp()
        };
        
        // Add features array
        const featureCount = Math.max(5, Math.floor(targetSizeBytes / 2000));
        expanded.features = [];
        for (let i = 0; i < featureCount; i++) {
            expanded.features.push(randomString(15));
        }
        
        // Add service history array
        const historyCount = Math.max(2, Math.floor(targetSizeBytes / 3000));
        expanded.serviceHistory = [];
        for (let i = 0; i < historyCount; i++) {
            expanded.serviceHistory.push({
                serviceId: `SVC-${randomString(8)}`,
                serviceDate: generateTimestamp(),
                serviceType: randomString(10),
                mileage: randomIntBetween(0, 100000),
                cost: randomIntBetween(100, 1000),
                description: randomString(50),
                technician: randomString(15)
            });
        }
    } else if (expanded.id && (expanded.id.includes('loan') || expanded.id.includes('payment'))) {
        // Add loan-specific nested data
        expanded.financialInstitution = {
            name: randomString(15),
            routingNumber: randomString(9),
            accountNumber: randomString(12),
            contact: {
                phone: `+1-555-${randomString(7)}`,
                email: `${randomString(10)}@bank.com`
            }
        };
        
        expanded.paymentHistory = [];
        const historyCount = Math.max(3, Math.floor(targetSizeBytes / 2000));
        for (let i = 0; i < historyCount; i++) {
            expanded.paymentHistory.push({
                paymentId: `PAY-${randomString(8)}`,
                amount: (100 + Math.random() * 2000).toFixed(2),
                date: generateTimestamp(),
                status: 'completed',
                transactionId: randomString(16)
            });
        }
        
        expanded.terms = {
            interestRate: (Math.random() * 10).toFixed(2),
            termMonths: randomIntBetween(12, 84),
            monthlyPayment: (200 + Math.random() * 800).toFixed(2),
            startDate: generateTimestamp(),
            endDate: generateTimestamp()
        };
    } else if (expanded.id && expanded.id.includes('service')) {
        // Add service-specific nested data
        expanded.dealer = {
            id: `DEALER-${randomString(8)}`,
            name: randomString(20),
            address: {
                street: `${randomIntBetween(1, 9999)} ${randomString(10)} Avenue`,
                city: randomString(12),
                state: randomString(2).toUpperCase(),
                zipCode: randomString(5)
            },
            phone: `+1-555-${randomString(7)}`,
            email: `${randomString(10)}@dealer.com`
        };
        
        expanded.parts = [];
        const partsCount = Math.max(2, Math.floor(targetSizeBytes / 1500));
        for (let i = 0; i < partsCount; i++) {
            expanded.parts.push({
                partId: `PART-${randomString(8)}`,
                name: randomString(20),
                quantity: randomIntBetween(1, 5),
                cost: (10 + Math.random() * 200).toFixed(2),
                manufacturer: randomString(15)
            });
        }
        
        expanded.technician = {
            id: `TECH-${randomString(8)}`,
            name: randomString(15),
            certification: randomString(10),
            experience: randomIntBetween(1, 20)
        };
    }
    
    // Add metadata and padding to reach target size
    expanded.metadata = {
        createdAt: generateTimestamp(),
        updatedAt: generateTimestamp(),
        createdBy: randomString(10),
        source: randomString(15),
        dataVersion: '1.0',
        tags: []
    };
    
    // Calculate current size and add padding if needed
    // In k6, we approximate byte size using string length (UTF-8 encoding)
    // Most characters are 1 byte, so this is a reasonable approximation
    const currentJson = JSON.stringify(expanded);
    const currentSize = currentJson.length; // Approximate byte size
    
    if (currentSize < targetSizeBytes) {
        const paddingNeeded = targetSizeBytes - currentSize;
        // Add padding field with random data
        const paddingChar = 'A';
        const paddingSize = Math.max(100, paddingNeeded - 50); // Leave some room for JSON structure
        expanded._padding = paddingChar.repeat(paddingSize);
    }
    
    // Final size check - if still too small, add more nested data
    let finalJson = JSON.stringify(expanded);
    let finalSize = finalJson.length; // Approximate byte size
    
    if (finalSize < targetSizeBytes) {
        // Add additional nested objects
        expanded.additionalData = {};
        const additionalNeeded = targetSizeBytes - finalSize;
        const additionalFields = Math.ceil(additionalNeeded / 100);
        
        for (let i = 0; i < additionalFields; i++) {
            expanded.additionalData[`field${i}`] = randomString(80);
        }
        
        finalJson = JSON.stringify(expanded);
        finalSize = finalJson.length; // Approximate byte size
    }
    
    return expanded;
}

/**
 * Generate event payload for REST API
 * Supports configurable payload size via PAYLOAD_SIZE environment variable
 */
export function generateEventPayload() {
    const targetSize = getTargetPayloadSize();
    
    const eventTypes = ['CarCreated', 'LoanCreated', 'LoanPaymentSubmitted', 'ServiceDone'];
    const eventType = eventTypes[randomIntBetween(0, eventTypes.length - 1)];
    const entityId = `${eventType.toLowerCase().replace(/created|submitted|done/g, '')}-${randomString(8)}-${Date.now()}`;
    const timestamp = generateTimestamp();
    const uuid = generateUUID();
    
    // Determine entity type based on event type
    let entityType = eventType;
    if (eventType.includes('Created')) {
        entityType = eventType.replace('Created', '');
    } else if (eventType.includes('Submitted')) {
        entityType = eventType.replace('Submitted', '');
    } else if (eventType.includes('Done')) {
        entityType = eventType.replace('Done', '');
    }
    
    // Generate updated attributes based on entity type
    const updatedAttributes = {
        id: entityId,
        timestamp: timestamp,
    };
    
    if (entityType === 'Loan' || entityType === 'LoanPayment') {
        updatedAttributes.balance = (1000 + Math.random() * 50000).toFixed(2);
        updatedAttributes.lastPaidDate = timestamp;
        if (eventType === 'LoanPaymentSubmitted') {
            updatedAttributes.paymentAmount = (100 + Math.random() * 2000).toFixed(2);
        }
    } else if (entityType === 'Service') {
        updatedAttributes.serviceCost = (50 + Math.random() * 500).toFixed(2);
    } else if (entityType === 'Car') {
        updatedAttributes.model = `Model-${randomString(6)}`;
        updatedAttributes.year = randomIntBetween(2010, 2024);
    }
    
    // Expand attributes to target size if specified
    const expandedAttributes = expandAttributesToSize(updatedAttributes, targetSize);
    
    const payload = {
        eventHeader: {
            uuid: uuid,
            eventName: eventType,
            createdDate: timestamp,
            savedDate: timestamp,
            eventType: eventType
        },
        eventBody: {
            entities: [{
                entityType: entityType,
                entityId: entityId,
                updatedAttributes: expandedAttributes
            }]
        }
    };
    
    const payloadJson = JSON.stringify(payload);
    
    // If target size is specified, ensure we meet it (accounting for event structure overhead)
    if (targetSize) {
        const currentSize = payloadJson.length; // Approximate byte size
        if (currentSize < targetSize) {
            // Re-expand with adjusted target to account for event structure
            const attributesSize = JSON.stringify(expandedAttributes).length;
            const attributesTarget = targetSize - (currentSize - attributesSize);
            const finalAttributes = expandAttributesToSize(updatedAttributes, attributesTarget);
            payload.eventBody.entities[0].updatedAttributes = finalAttributes;
            return JSON.stringify(payload);
        }
    }
    
    return payloadJson;
}

/**
 * Generate gRPC event request payload (JSON format for k6 gRPC)
 * Supports configurable payload size via PAYLOAD_SIZE environment variable
 */
export function generateGrpcEventPayload() {
    const targetSize = getTargetPayloadSize();
    
    const eventTypes = ['CarCreated', 'LoanCreated', 'LoanPaymentSubmitted', 'ServiceDone'];
    const eventType = eventTypes[randomIntBetween(0, eventTypes.length - 1)];
    const entityId = `${eventType.toLowerCase().replace(/created|submitted|done/g, '')}-${randomString(8)}-${Date.now()}`;
    const timestamp = generateTimestamp();
    const uuid = generateUUID();
    
    // Determine entity type based on event type
    let entityType = eventType;
    if (eventType.includes('Created')) {
        entityType = eventType.replace('Created', '');
    } else if (eventType.includes('Submitted')) {
        entityType = eventType.replace('Submitted', '');
    } else if (eventType.includes('Done')) {
        entityType = eventType.replace('Done', '');
    }
    
    // Generate updated attributes as a map
    const updatedAttributes = {
        id: entityId,
        timestamp: timestamp,
    };
    
    if (entityType === 'Loan' || entityType === 'LoanPayment') {
        updatedAttributes.balance = (1000 + Math.random() * 50000).toFixed(2);
        updatedAttributes.lastPaidDate = timestamp;
        if (eventType === 'LoanPaymentSubmitted') {
            updatedAttributes.paymentAmount = (100 + Math.random() * 2000).toFixed(2);
        }
    } else if (entityType === 'Service') {
        updatedAttributes.serviceCost = (50 + Math.random() * 500).toFixed(2);
    } else if (entityType === 'Car') {
        updatedAttributes.model = `Model-${randomString(6)}`;
        updatedAttributes.year = randomIntBetween(2010, 2024).toString();
    }
    
    // Expand attributes to target size if specified
    const expandedAttributes = expandAttributesToSize(updatedAttributes, targetSize);
    
    // For gRPC, convert nested objects to JSON strings (proto expects map<string, string>)
    const grpcAttributes = stringifyAttributesForGrpc(expandedAttributes);
    
    const payload = {
        event_header: {
            uuid: uuid,
            event_name: eventType,
            created_date: timestamp,
            saved_date: timestamp,
            event_type: eventType
        },
        event_body: {
            entities: [{
                entity_type: entityType,
                entity_id: entityId,
                updated_attributes: grpcAttributes
            }]
        }
    };
    
    // If target size is specified, ensure we meet it (accounting for event structure overhead)
    if (targetSize) {
        const payloadJson = JSON.stringify(payload);
        const currentSize = payloadJson.length; // Approximate byte size
        if (currentSize < targetSize) {
            // Re-expand with adjusted target to account for event structure
            const attributesSize = JSON.stringify(grpcAttributes).length;
            const attributesTarget = targetSize - (currentSize - attributesSize);
            const finalAttributes = expandAttributesToSize(updatedAttributes, attributesTarget);
            // Convert to gRPC format
            payload.event_body.entities[0].updated_attributes = stringifyAttributesForGrpc(finalAttributes);
        }
    }
    
    return payload;
}

