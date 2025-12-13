use crate::error::AppError;
use crate::models::{EntityUpdate, Event, EventBody, EventHeader};
use crate::repository::DuplicateEventError;
use crate::service::EventProcessingService;
use crate::repository::BusinessEventRepository;
use crate::constants::API_NAME;
use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::PgPool;
use tonic::{Request, Response, Status};

pub mod proto {
    tonic::include_proto!("com.example.grpc");
}

use proto::{
    event_service_server::{EventService, EventServiceServer},
    EventRequest, EventResponse, HealthRequest, HealthResponse,
};

pub struct EventServiceImpl {
    event_processing_service: EventProcessingService,
}

impl EventServiceImpl {
    pub fn new(business_event_repo: BusinessEventRepository, pool: PgPool) -> Self {
        let event_processing_service = EventProcessingService::new(business_event_repo, pool);
        Self {
            event_processing_service,
        }
    }
}

#[tonic::async_trait]
impl EventService for EventServiceImpl {
    async fn process_event(
        &self,
        request: Request<EventRequest>,
    ) -> Result<Response<EventResponse>, Status> {
        let req = request.into_inner();

        let event_name = req.event_header.as_ref()
            .map(|h| h.event_name.as_str())
            .unwrap_or("unknown");
        tracing::info!("{} Received gRPC event: {}", API_NAME, event_name);

        // Validate request
        let event_header_proto = req.event_header.ok_or_else(|| {
            Status::from(AppError::Validation("Invalid event: missing eventHeader".to_string()))
        })?;

        // Validate event_name is not empty
        if event_header_proto.event_name.is_empty() {
            return Err(Status::invalid_argument("Invalid event: eventName cannot be empty"));
        }

        let event_body_proto = req.event_body.ok_or_else(|| {
            Status::from(AppError::Validation("Invalid event: missing eventBody".to_string()))
        })?;

        // Validate entities list is not empty
        if event_body_proto.entities.is_empty() {
            return Err(Status::invalid_argument("Invalid event: entities list cannot be empty"));
        }

        // Convert protobuf EventRequest to internal Event model
        let event = convert_proto_to_event(event_header_proto, event_body_proto)
            .map_err(|e| Status::invalid_argument(format!("Failed to convert event: {}", e)))?;

        // Process event
        match self.event_processing_service.process_event(event).await {
            Ok(_) => {
                Ok(Response::new(EventResponse {
                    success: true,
                    message: "Event processed successfully".to_string(),
                }))
            }
            Err(e) => {
                // Check if it's a duplicate event error
                if let Some(dup_err) = e.downcast_ref::<DuplicateEventError>() {
                    return Err(Status::already_exists(format!(
                        "Event with ID '{}' already exists",
                        dup_err.event_id
                    )));
                }
                Err(Status::from(AppError::Internal(e)))
            }
        }
    }

    async fn health_check(
        &self,
        _request: Request<HealthRequest>,
    ) -> Result<Response<HealthResponse>, Status> {
        tracing::info!("{} Health check requested", API_NAME);

        Ok(Response::new(HealthResponse {
            healthy: true,
            message: "Producer gRPC API is healthy".to_string(),
        }))
    }
}

fn convert_proto_to_event(
    header: proto::EventHeader,
    body: proto::EventBody,
) -> Result<Event, String> {
    // Convert EventHeader
    let event_header = EventHeader {
        uuid: if header.uuid.is_empty() {
            None
        } else {
            Some(header.uuid)
        },
        event_name: header.event_name,
        created_date: parse_datetime_option(&header.created_date),
        saved_date: parse_datetime_option(&header.saved_date),
        event_type: if header.event_type.is_empty() {
            None
        } else {
            Some(header.event_type)
        },
    };

    // Convert EntityUpdate list
    let mut entities = Vec::new();
    for entity_proto in body.entities {
        // Validate entity_type and entity_id are not empty
        if entity_proto.entity_type.is_empty() {
            return Err("Invalid entity: entityType cannot be empty".to_string());
        }
        if entity_proto.entity_id.is_empty() {
            return Err("Invalid entity: entityId cannot be empty".to_string());
        }

        // Convert map<string, string> to serde_json::Value
        let updated_attributes: Value = serde_json::to_value(entity_proto.updated_attributes)
            .map_err(|e| format!("Failed to convert updated_attributes: {}", e))?;

        entities.push(EntityUpdate {
            entity_type: entity_proto.entity_type,
            entity_id: entity_proto.entity_id,
            updated_attributes,
        });
    }

    let event_body = EventBody { entities };

    Ok(Event {
        event_header,
        event_body,
    })
}

fn parse_datetime_option(dt_str: &str) -> Option<DateTime<Utc>> {
    if dt_str.is_empty() {
        return None;
    }

    // Try ISO 8601 formats
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(dt_str) {
        return Some(dt.with_timezone(&Utc));
    }
    if let Ok(dt) = chrono::DateTime::parse_from_str(dt_str, "%Y-%m-%dT%H:%M:%S%.fZ") {
        return Some(dt.with_timezone(&Utc));
    }

    // Try parsing as Unix timestamp (milliseconds)
    if let Ok(ms) = dt_str.parse::<i64>() {
        let secs = ms / 1000;
        let nsecs = ((ms % 1000) * 1_000_000) as u32;
        if let Some(dt) = chrono::DateTime::from_timestamp(secs, nsecs) {
            return Some(dt);
        }
    }

    None
}

pub fn create_service(
    business_event_repo: BusinessEventRepository,
    pool: PgPool,
) -> EventServiceServer<EventServiceImpl> {
    EventServiceServer::new(EventServiceImpl::new(business_event_repo, pool))
}
