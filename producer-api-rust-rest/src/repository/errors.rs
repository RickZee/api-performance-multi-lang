use thiserror::Error;

#[derive(Debug, Error)]
#[error("Event with ID '{event_id}' already exists")]
pub struct DuplicateEventError {
    pub event_id: String,
}

impl DuplicateEventError {
    pub fn new(event_id: String) -> Self {
        Self { event_id }
    }
}

