use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use validator::Validate;

// Custom deserializer that accepts both ISO 8601 strings and Unix timestamps (milliseconds)
fn deserialize_datetime_option<'de, D>(deserializer: D) -> Result<Option<DateTime<Utc>>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;
    
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum DateTimeOrTimestamp {
        String(String),
        Number(i64),
    }
    
    match DateTimeOrTimestamp::deserialize(deserializer)? {
        DateTimeOrTimestamp::String(s) => {
            // First try parsing as ISO 8601
            if let Ok(dt) = DateTime::parse_from_rfc3339(&s) {
                return Ok(Some(dt.with_timezone(&Utc)));
            }
            if let Ok(dt) = DateTime::parse_from_str(&s, "%Y-%m-%dT%H:%M:%S%.fZ") {
                return Ok(Some(dt.with_timezone(&Utc)));
            }
            // If that fails, try parsing as a numeric string (timestamp in milliseconds)
            if let Ok(ms) = s.parse::<i64>() {
                let secs = ms / 1000;
                let nsecs = ((ms % 1000) * 1_000_000) as u32;
                if let Some(dt) = DateTime::from_timestamp(secs, nsecs) {
                    return Ok(Some(dt));
                }
            }
            Err(D::Error::custom(format!("Invalid date format: {}", s)))
        }
        DateTimeOrTimestamp::Number(ms) => {
            // Treat as Unix timestamp in milliseconds
            let secs = ms / 1000;
            let nsecs = ((ms % 1000) * 1_000_000) as u32;
            DateTime::from_timestamp(secs, nsecs)
                .map(|dt| Some(dt))
                .ok_or_else(|| D::Error::custom(format!("Invalid timestamp: {}", ms)))
        }
    }
}

// Custom deserializer for EntityHeader dates
fn deserialize_datetime_required<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;
    
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum DateTimeOrTimestamp {
        String(String),
        Number(i64),
    }
    
    match DateTimeOrTimestamp::deserialize(deserializer)? {
        DateTimeOrTimestamp::String(s) => {
            // First try parsing as ISO 8601
            if let Ok(dt) = DateTime::parse_from_rfc3339(&s) {
                return Ok(dt.with_timezone(&Utc));
            }
            if let Ok(dt) = DateTime::parse_from_str(&s, "%Y-%m-%dT%H:%M:%S%.fZ") {
                return Ok(dt.with_timezone(&Utc));
            }
            // If that fails, try parsing as a numeric string (timestamp in milliseconds)
            if let Ok(ms) = s.parse::<i64>() {
                let secs = ms / 1000;
                let nsecs = ((ms % 1000) * 1_000_000) as u32;
                if let Some(dt) = DateTime::from_timestamp(secs, nsecs) {
                    return Ok(dt);
                }
            }
            Err(D::Error::custom(format!("Invalid date format: {}", s)))
        }
        DateTimeOrTimestamp::Number(ms) => {
            // Treat as Unix timestamp in milliseconds
            let secs = ms / 1000;
            let nsecs = ((ms % 1000) * 1_000_000) as u32;
            DateTime::from_timestamp(secs, nsecs)
                .ok_or_else(|| D::Error::custom(format!("Invalid timestamp: {}", ms)))
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct Event {
    #[serde(rename = "eventHeader")]
    pub event_header: EventHeader,
    pub entities: Vec<Entity>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventHeader {
    pub uuid: Option<String>,
    #[serde(rename = "eventName")]
    pub event_name: String,
    #[serde(rename = "createdDate", deserialize_with = "deserialize_datetime_option")]
    pub created_date: Option<DateTime<Utc>>,
    #[serde(rename = "savedDate", deserialize_with = "deserialize_datetime_option")]
    pub saved_date: Option<DateTime<Utc>>,
    #[serde(rename = "eventType")]
    pub event_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityHeader {
    #[serde(rename = "entityId")]
    pub entity_id: String,
    #[serde(rename = "entityType")]
    pub entity_type: String,
    #[serde(rename = "createdAt", deserialize_with = "deserialize_datetime_required")]
    pub created_at: DateTime<Utc>,
    #[serde(rename = "updatedAt", deserialize_with = "deserialize_datetime_required")]
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Entity {
    #[serde(rename = "entityHeader")]
    pub entity_header: EntityHeader,
    // Additional entity-specific properties
    #[serde(flatten)]
    pub properties: serde_json::Value,
}

impl<'de> Deserialize<'de> for Entity {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        use serde::de::Error;
        let value: serde_json::Value = Deserialize::deserialize(deserializer)?;
        
        // Extract entityHeader
        let entity_header = value
            .get("entityHeader")
            .ok_or_else(|| D::Error::custom("missing entityHeader"))?
            .clone();
        let entity_header: EntityHeader = serde_json::from_value(entity_header)
            .map_err(|e| D::Error::custom(format!("invalid entityHeader: {}", e)))?;
        
        // Create a new value without entityHeader for properties
        let mut properties = value.clone();
        properties.as_object_mut()
            .ok_or_else(|| D::Error::custom("entity must be an object"))?
            .remove("entityHeader");
        
        Ok(Entity {
            entity_header,
            properties,
        })
    }
}

