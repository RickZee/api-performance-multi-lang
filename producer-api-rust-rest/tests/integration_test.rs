use axum::Router;
use producer_api_rust::{
    handlers::{event, health},
    models,
    repository::CarEntityRepository,
    service::EventProcessingService,
};
use serde_json::json;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;
use reqwest::Client;
use std::net::SocketAddr;
use tokio::net::TcpListener;

async fn setup_test_database() -> PgPool {
    // Use the existing Docker database (requires docker-compose database to be running)
    let database_url = "postgresql://postgres:password@localhost:5432/car_entities";

    // Retry connection with exponential backoff
    // Use a smaller connection pool for tests to avoid connection exhaustion
    let mut retries = 0;
    let max_retries = 10;
    let pool = loop {
        match PgPoolOptions::new()
            .max_connections(2)  // Reduced for tests
            .min_connections(1)
            .acquire_timeout(Duration::from_secs(10))
            .idle_timeout(Duration::from_secs(30))
            .max_lifetime(Duration::from_secs(60))
            .connect(database_url)
            .await
        {
            Ok(pool) => {
                // Test the connection
                match sqlx::query("SELECT 1").execute(&pool).await {
                    Ok(_) => break pool,
                    Err(e) => {
                        if retries >= max_retries {
                            panic!("Failed to execute test query after {} retries: {}", max_retries, e);
                        }
                        retries += 1;
                        let delay = Duration::from_millis(500 * retries);
                        tokio::time::sleep(delay).await;
                    }
                }
            }
            Err(e) => {
                if retries >= max_retries {
                    panic!("Failed to connect to test database after {} retries: {}. Make sure the database is running with: docker-compose --profile large up -d postgres-large", max_retries, e);
                }
                retries += 1;
                let delay = Duration::from_millis(500 * retries); // Linear backoff
                tokio::time::sleep(delay).await;
            }
        }
    };

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

async fn create_test_server(pool: PgPool) -> SocketAddr {
    let repository = CarEntityRepository::new(pool);
    let service = EventProcessingService::new(repository);

    let app = Router::new()
        .nest("/api/v1/events", event::router())
        .nest("/api/v1/events", health::router())
        .with_state(service);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    
    // Create a shutdown signal that will never trigger (test will complete first)
    let (tx, rx) = tokio::sync::oneshot::channel::<()>();
    let shutdown = async {
        rx.await.ok();
    };
    
    // Spawn the server task - it will run until the test completes
    tokio::spawn(async move {
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown)
            .await
            .unwrap();
    });
    
    // Give the server a moment to start and verify it's listening
    tokio::time::sleep(Duration::from_millis(300)).await;
    
    // Verify server is actually listening by trying to connect
    let mut retries = 0;
    while retries < 10 {
        if tokio::net::TcpStream::connect(addr).await.is_ok() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
        retries += 1;
    }
    
    // Prevent tx from being dropped (which would trigger shutdown)
    std::mem::forget(tx);
    
    addr
}

fn create_test_event() -> serde_json::Value {
    json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "LoanPaymentSubmitted",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "loan-12345",
                    "entityType": "Loan",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "balance": 24439.75,
                "lastPaidDate": "2024-01-15T10:30:00Z"
            }
        ]
    })
}

#[tokio::test]
async fn test_process_event_with_new_entity_should_create_entity_in_database() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool.clone()).await;
    let client = Client::new();

    let event = create_test_event();

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    let status = response.status();
    if status != 200 {
        let error_text = response.text().await.unwrap();
        panic!("Request failed with status {}: {}", status, error_text);
    }
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["success"], true);
    assert_eq!(body["message"], "Event processed successfully");

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
async fn test_process_event_with_existing_entity_should_update_entity() {
    let pool = setup_test_database().await;
    let repository = CarEntityRepository::new(pool.clone());
    
    // Create existing entity
    let existing_entity = models::CarEntity::new(
        "loan-12345".to_string(),
        "Loan".to_string(),
        r#"{"balance": 25000.00, "status": "active"}"#.to_string(),
    );
    repository
        .create(&existing_entity)
        .await
        .expect("Failed to create existing entity");

    let addr = create_test_server(pool.clone()).await;
    let client = Client::new();

    let event = create_test_event();

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    let status = response.status();
    if status != 200 {
        let error_text = response.text().await.unwrap();
        panic!("Request failed with status {}: {}", status, error_text);
    }
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["success"], true);

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
async fn test_process_event_with_multiple_entities_should_process_all_entities() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool.clone()).await;
    let client = Client::new();

    let event = json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "LoanPaymentSubmitted",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "loan-12345",
                    "entityType": "Loan",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "balance": 24439.75,
                "lastPaidDate": "2024-01-15T10:30:00Z"
            },
            {
                "entityHeader": {
                    "entityId": "payment-12345",
                    "entityType": "LoanPayment",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "paymentAmount": 560.25,
                "paymentDate": "2024-01-15T10:30:00Z",
                "paymentMethod": "ACH"
            }
        ]
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    let status = response.status();
    if status != 200 {
        let error_text = response.text().await.unwrap();
        panic!("Request failed with status {}: {}", status, error_text);
    }
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["success"], true);

    // Verify both entities were created
    let repository = CarEntityRepository::new(pool);
    
    let loan_entity = repository
        .find_by_entity_type_and_id("Loan", "loan-12345")
        .await
        .expect("Failed to find loan entity")
        .expect("Loan entity should exist");
    assert_eq!(loan_entity.id, "loan-12345");

    let payment_entity = repository
        .find_by_entity_type_and_id("LoanPayment", "payment-12345")
        .await
        .expect("Failed to find payment entity")
        .expect("Payment entity should exist");
    assert_eq!(payment_entity.id, "payment-12345");
}

#[tokio::test]
async fn test_process_event_with_invalid_event_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    // Invalid event - missing required fields
    let invalid_event = json!({
        "eventHeader": null,
        "entities": null
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&invalid_event)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422); // 422 Unprocessable Entity is correct for validation errors
}

#[tokio::test]
async fn test_health_check_should_return_ok() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let response = client
        .get(format!("http://{}/api/v1/events/health", addr))
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["status"], "healthy");
    assert_eq!(body["message"], "Producer API is healthy");
}

#[tokio::test]
async fn test_process_bulk_events_with_valid_events_should_process_all_events() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let events = vec![
        create_test_event(),
        json!({
            "eventHeader": {
                "uuid": "660e8400-e29b-41d4-a716-446655440001",
                "eventName": "LoanPaymentSubmitted",
                "createdDate": "2024-01-15T10:30:00Z",
                "savedDate": "2024-01-15T10:30:05Z",
                "eventType": "LoanPaymentSubmitted"
            },
            "entities": [
                {
                    "entityHeader": {
                        "entityId": "payment-67890",
                        "entityType": "LoanPayment",
                        "createdAt": "2024-01-15T10:30:00Z",
                        "updatedAt": "2024-01-15T10:30:00Z"
                    },
                    "paymentAmount": 560.25,
                    "paymentDate": "2024-01-15T10:30:00Z"
                }
            ]
        }),
    ];

    let response = client
        .post(format!("http://{}/api/v1/events/bulk", addr))
        .json(&events)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["success"], true);
    assert_eq!(body["message"], "All events processed successfully");
    assert_eq!(body["processedCount"], 2);
    assert_eq!(body["failedCount"], 0);
    assert!(body["batchId"].is_string());
}

#[tokio::test]
async fn test_process_bulk_events_with_mixed_valid_and_invalid_events_should_process_partially() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let events = vec![
        create_test_event(),
        json!({
            "eventHeader": {
                "uuid": "660e8400-e29b-41d4-a716-446655440001",
                "eventName": "",  // Empty event name - invalid
                "createdDate": "2024-01-15T10:30:00Z",
                "savedDate": "2024-01-15T10:30:05Z",
                "eventType": "LoanPaymentSubmitted"
            },
            "entities": []
        }),
    ];

    let response = client
        .post(format!("http://{}/api/v1/events/bulk", addr))
        .json(&events)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 200);
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["success"], false);
    assert_eq!(body["processedCount"], 1);
    assert_eq!(body["failedCount"], 1);
    assert!(body["batchId"].is_string());
}

#[tokio::test]
async fn test_process_bulk_events_with_empty_list_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let events: Vec<serde_json::Value> = vec![];

    let response = client
        .post(format!("http://{}/api/v1/events/bulk", addr))
        .json(&events)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422);
}

#[tokio::test]
async fn test_process_event_with_empty_entities_list_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let event = json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "LoanPaymentSubmitted",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": []
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422);
}

#[tokio::test]
async fn test_process_event_with_empty_event_name_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let event = json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "loan-12345",
                    "entityType": "Loan",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "balance": 24439.75
            }
        ]
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422);
}

#[tokio::test]
async fn test_process_event_with_empty_entity_type_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let event = json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "LoanPaymentSubmitted",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "loan-12345",
                    "entityType": "",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "balance": 24439.75
            }
        ]
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422);
}

#[tokio::test]
async fn test_process_event_with_empty_entity_id_should_return_error() {
    let pool = setup_test_database().await;
    let addr = create_test_server(pool).await;
    let client = Client::new();

    let event = json!({
        "eventHeader": {
            "uuid": "550e8400-e29b-41d4-a716-446655440000",
            "eventName": "LoanPaymentSubmitted",
            "createdDate": "2024-01-15T10:30:00Z",
            "savedDate": "2024-01-15T10:30:05Z",
            "eventType": "LoanPaymentSubmitted"
        },
        "entities": [
            {
                "entityHeader": {
                    "entityId": "",
                    "entityType": "Loan",
                    "createdAt": "2024-01-15T10:30:00Z",
                    "updatedAt": "2024-01-15T10:30:00Z"
                },
                "balance": 24439.75
            }
        ]
    });

    let response = client
        .post(format!("http://{}/api/v1/events", addr))
        .json(&event)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), 422);
}
