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
 * Generate event payload for REST API
 */
export function generateEventPayload() {
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
    
    return JSON.stringify({
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
                updatedAttributes: updatedAttributes
            }]
        }
    });
}

/**
 * Generate gRPC event request payload (JSON format for k6 gRPC)
 */
export function generateGrpcEventPayload() {
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
    
    return {
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
                updated_attributes: updatedAttributes
            }]
        }
    };
}

