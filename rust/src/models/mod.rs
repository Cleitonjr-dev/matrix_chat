use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub user_id: String,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomInfo {
    pub room_id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub event_id: String,
    pub sender: String,
    pub body: String,
    pub timestamp_millis: i64,
    pub reply_to_event_id: String,
    pub reply_to_body: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncEvent {
    pub kind: String,
    pub room_id: String,
    pub body: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_round_trips_through_json() {
        let message = Message {
            event_id: "$ev1".to_string(),
            sender: "@alice:example.org".to_string(),
            body: "hello".to_string(),
            timestamp_millis: 1_700_000_000_000,
            reply_to_event_id: String::new(),
            reply_to_body: String::new(),
        };
        let json = serde_json::to_string(&message).unwrap();
        let back: Message = serde_json::from_str(&json).unwrap();
        assert_eq!(back.body, "hello");
        assert_eq!(back.event_id, "$ev1");
    }
}
