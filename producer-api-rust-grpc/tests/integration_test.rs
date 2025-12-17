use producer_api_rust_grpc::{
    repository::{CarEntity, CarEntityRepository},
    service::event_service::create_service,
};
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;
use tonic::transport::{Channel, Server};
use std::net::SocketAddr;

use producer_api_rust_grpc::service::event_service::{
    proto::{
        event_service_client::EventServiceClient,
        EventRequest, EventResponse, HealthRequest, HealthResponse, EventHeader, EventBody, EntityUpdate,
    },
};

async fn setup_test_database() -> PgPool {
    // Use the existing Docker database (requires docker-compose database to be running)
    let database_url = "postgresql://postgres:password@localhost:5432/car_entities";

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await
        .expect("Failed to connect to test database");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    // Clean up test data
    sqlx::query("DELETE FROM car_entities")
        .execute(&pool)
        .await
        .expect("Failed to clean up test data");
    
    pool
}

async fn create_test_server(pool: PgPool) -> (EventServiceClient<Channel>, SocketAddr) {
    let repository = CarEntityRepository::new(pool);
    let service = create_service(repository);

    // Find an available port
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        Server::builder()
            .add_service(service)
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    // Wait for server to start
    tokio::time::sleep(Duration::from_millis(200)).await;

    let client = EventServiceClient::connect(format!("http://{}", addr))
        .await
        .expect("Failed to connect to test server");

    (client, addr)
}

fn create_valid_event_request() -> EventRequest {
    let mut attributes = std::collections::HashMap::new();
    attributes.insert("balance".to_string(), "24439.75".to_string());
    attributes.insert("lastPaidDate".to_string(), "2024-01-15T10:30:00Z".to_string());

    let entity_update = EntityUpdate {
        entity_type: "Loan".to_string(),
        entity_id: "loan-12345".to_string(),
        updated_attributes: attributes,
    };

    let event_body = EventBody {
        entities: vec![entity_update],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "LoanPaymentSubmitted".to_string(),
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    }
}

#[tokio::test]
async fn test_process_event_with_valid_event_should_process_successfully() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool.clone()).await;

    let request = create_valid_event_request();

    let response = client
        .process_event(tonic::Request::new(request))
        .await
        .expect("Failed to process event");

    let response = response.into_inner();
    assert!(response.success);
    assert_eq!(response.message, "Event processed successfully");

    // Verify entity was created in database
    let repository = CarEntityRepository::new(pool);
    let entity = repository
        .find_by_entity_type_and_id("Loan", "loan-12345")
        .await
        .expect("Failed to find entity")
        .expect("Entity should exist");

    assert_eq!(entity.entity_type, "Loan");
    assert_eq!(entity.id, "loan-12345");
    assert!(entity.data.contains("24439.75"));
}

#[tokio::test]
async fn test_process_event_with_invalid_event_should_return_error() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    // Invalid event - missing event header
    let request = EventRequest {
        event_header: None,
        event_body: Some(EventBody {
            entities: vec![],
        }),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await;

    assert!(response.is_err());
    let status = response.unwrap_err();
    assert!(status.message().contains("Invalid event"));
}

#[tokio::test]
async fn test_process_event_with_existing_entity_should_update_entity() {
    let pool = setup_test_database().await;
    let repository = CarEntityRepository::new(pool.clone());
    
    // Create existing entity
    let existing_entity = CarEntity::new(
        "loan-12345".to_string(),
        "Loan".to_string(),
        r#"{"balance": 25000.00, "status": "active"}"#.to_string(),
    );
    repository
        .create(&existing_entity)
        .await
        .expect("Failed to create existing entity");

    let (mut client, _addr) = create_test_server(pool.clone()).await;

    let request = create_valid_event_request();

    let response = client
        .process_event(tonic::Request::new(request))
        .await
        .expect("Failed to process event");

    let response = response.into_inner();
    assert!(response.success);

    // Verify entity was updated
    let updated_entity = repository
        .find_by_entity_type_and_id("Loan", "loan-12345")
        .await
        .expect("Failed to find entity")
        .expect("Entity should exist");

    assert!(updated_entity.data.contains("24439.75"));
    assert!(updated_entity.updated_at.is_some());
}

#[tokio::test]
async fn test_health_check_should_return_healthy() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    let request = HealthRequest {
        service: "producer-api-grpc".to_string(),
    };

    let response = client
        .health_check(tonic::Request::new(request))
        .await
        .expect("Failed to perform health check");

    let response = response.into_inner();
    assert!(response.healthy);
    assert_eq!(response.message, "Producer gRPC API is healthy");
}

#[tokio::test]
async fn test_process_event_with_multiple_entities_should_process_all_entities() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool.clone()).await;

    let mut loan_attributes = std::collections::HashMap::new();
    loan_attributes.insert("balance".to_string(), "24439.75".to_string());
    loan_attributes.insert("lastPaidDate".to_string(), "2024-01-15T10:30:00Z".to_string());

    let loan_entity = EntityUpdate {
        entity_type: "Loan".to_string(),
        entity_id: "loan-12345".to_string(),
        updated_attributes: loan_attributes,
    };

    let mut payment_attributes = std::collections::HashMap::new();
    payment_attributes.insert("paymentAmount".to_string(), "560.25".to_string());
    payment_attributes.insert("paymentDate".to_string(), "2024-01-15T10:30:00Z".to_string());
    payment_attributes.insert("paymentMethod".to_string(), "ACH".to_string());

    let payment_entity = EntityUpdate {
        entity_type: "LoanPayment".to_string(),
        entity_id: "payment-12345".to_string(),
        updated_attributes: payment_attributes,
    };

    let event_body = EventBody {
        entities: vec![loan_entity, payment_entity],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "LoanPaymentSubmitted".to_string(),
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    let request = EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await
        .expect("Failed to process event");

    let response = response.into_inner();
    assert!(response.success);
    assert_eq!(response.message, "Event processed successfully");

    // Verify both entities were created
    let repository = CarEntityRepository::new(pool);
    
    let loan_entity_db = repository
        .find_by_entity_type_and_id("Loan", "loan-12345")
        .await
        .expect("Failed to find loan entity")
        .expect("Loan entity should exist");
    assert_eq!(loan_entity_db.id, "loan-12345");

    let payment_entity_db = repository
        .find_by_entity_type_and_id("LoanPayment", "payment-12345")
        .await
        .expect("Failed to find payment entity")
        .expect("Payment entity should exist");
    assert_eq!(payment_entity_db.id, "payment-12345");
}

#[tokio::test]
async fn test_process_event_with_empty_entities_list_should_return_error() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    let event_body = EventBody {
        entities: vec![],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "LoanPaymentSubmitted".to_string(),
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    let request = EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await;

    assert!(response.is_err());
    let status = response.unwrap_err();
    assert!(status.message().contains("entities list cannot be empty"));
}

#[tokio::test]
async fn test_process_event_with_empty_event_name_should_return_error() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    let mut attributes = std::collections::HashMap::new();
    attributes.insert("balance".to_string(), "24439.75".to_string());

    let entity_update = EntityUpdate {
        entity_type: "Loan".to_string(),
        entity_id: "loan-12345".to_string(),
        updated_attributes: attributes,
    };

    let event_body = EventBody {
        entities: vec![entity_update],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "".to_string(), // Empty event name
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    let request = EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await;

    assert!(response.is_err());
    let status = response.unwrap_err();
    assert!(status.message().contains("eventName cannot be empty"));
}

#[tokio::test]
async fn test_process_event_with_empty_entity_type_should_return_error() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    let mut attributes = std::collections::HashMap::new();
    attributes.insert("balance".to_string(), "24439.75".to_string());

    let entity_update = EntityUpdate {
        entity_type: "".to_string(), // Empty entity type
        entity_id: "loan-12345".to_string(),
        updated_attributes: attributes,
    };

    let event_body = EventBody {
        entities: vec![entity_update],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "LoanPaymentSubmitted".to_string(),
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    let request = EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await;

    assert!(response.is_err());
    let status = response.unwrap_err();
    assert!(status.message().contains("entityType cannot be empty"));
}

#[tokio::test]
async fn test_process_event_with_empty_entity_id_should_return_error() {
    let pool = setup_test_database().await;
    let (mut client, _addr) = create_test_server(pool).await;

    let mut attributes = std::collections::HashMap::new();
    attributes.insert("balance".to_string(), "24439.75".to_string());

    let entity_update = EntityUpdate {
        entity_type: "Loan".to_string(),
        entity_id: "".to_string(), // Empty entity ID
        updated_attributes: attributes,
    };

    let event_body = EventBody {
        entities: vec![entity_update],
    };

    let event_header = EventHeader {
        uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
        event_name: "LoanPaymentSubmitted".to_string(),
        created_date: "2024-01-15T10:30:00Z".to_string(),
        saved_date: "2024-01-15T10:30:05Z".to_string(),
        event_type: "LoanPaymentSubmitted".to_string(),
    };

    let request = EventRequest {
        event_header: Some(event_header),
        event_body: Some(event_body),
    };

    let response = client
        .process_event(tonic::Request::new(request))
        .await;

    assert!(response.is_err());
    let status = response.unwrap_err();
    assert!(status.message().contains("entityId cannot be empty"));
}
