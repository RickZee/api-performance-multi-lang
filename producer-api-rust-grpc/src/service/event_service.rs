use crate::error::AppError;
use crate::service::EventProcessingService;
use crate::repository::CarEntityRepository;
use std::collections::HashMap;
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
    pub fn new(repository: CarEntityRepository) -> Self {
        let event_processing_service = EventProcessingService::new(repository);
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
        tracing::info!("Received gRPC event: {}", event_name);

        // Validate request
        let event_header = req.event_header.ok_or_else(|| {
            Status::from(AppError::Validation("Invalid event: missing eventHeader".to_string()))
        })?;

        // Validate event_name is not empty
        if event_header.event_name.is_empty() {
            return Err(Status::invalid_argument("Invalid event: eventName cannot be empty"));
        }

        let event_body = req.event_body.ok_or_else(|| {
            Status::from(AppError::Validation("Invalid event: missing eventBody".to_string()))
        })?;

        // Validate entities list is not empty
        if event_body.entities.is_empty() {
            return Err(Status::invalid_argument("Invalid event: entities list cannot be empty"));
        }

        // Process each entity update
        for entity_update in event_body.entities {
            // Validate entity_type and entity_id are not empty
            if entity_update.entity_type.is_empty() {
                return Err(Status::invalid_argument("Invalid entity: entityType cannot be empty"));
            }
            if entity_update.entity_id.is_empty() {
                return Err(Status::invalid_argument("Invalid entity: entityId cannot be empty"));
            }

            let updated_attributes: HashMap<String, String> = entity_update.updated_attributes;
            
            self.event_processing_service
                .process_event(
                    &event_header.event_name,
                    &entity_update.entity_type,
                    &entity_update.entity_id,
                    &updated_attributes,
                )
                .await
                .map_err(|e| Status::from(AppError::Internal(e)))?;
        }

        Ok(Response::new(EventResponse {
            success: true,
            message: "Event processed successfully".to_string(),
        }))
    }

    async fn health_check(
        &self,
        _request: Request<HealthRequest>,
    ) -> Result<Response<HealthResponse>, Status> {
        tracing::info!("Health check requested");

        Ok(Response::new(HealthResponse {
            healthy: true,
            message: "Producer gRPC API is healthy".to_string(),
        }))
    }
}

pub fn create_service(repository: CarEntityRepository) -> EventServiceServer<EventServiceImpl> {
    EventServiceServer::new(EventServiceImpl::new(repository))
}

