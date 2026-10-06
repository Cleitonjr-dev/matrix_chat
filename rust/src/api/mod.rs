pub mod simple;

use futures_util::{pin_mut, StreamExt};

use crate::frb_generated::StreamSink;
use crate::matrix;
use crate::models::{Message, RoomInfo, SessionInfo, SyncEvent};

pub async fn login(
    homeserver: String,
    username: String,
    password: String,
    store_path: String,
    session_path: String,
) -> anyhow::Result<SessionInfo> {
    matrix::login(homeserver, username, password, store_path, session_path).await
}

pub async fn restore_session(
    homeserver: String,
    store_path: String,
    session_path: String,
) -> anyhow::Result<SessionInfo> {
    matrix::restore_session(homeserver, store_path, session_path).await
}

pub async fn list_rooms() -> anyhow::Result<Vec<RoomInfo>> {
    matrix::list_rooms().await
}

pub async fn get_messages(room_id: String, limit: u16) -> anyhow::Result<Vec<Message>> {
    matrix::get_messages(room_id, limit).await
}

pub async fn send_message(
    room_id: String,
    text: String,
    reply_to_event_id: Option<String>,
) -> anyhow::Result<()> {
    matrix::send_message(room_id, text, reply_to_event_id).await
}

pub async fn logout(session_path: String) -> anyhow::Result<()> {
    matrix::logout(session_path).await
}

pub fn start_sync(sink: StreamSink<SyncEvent>) -> anyhow::Result<()> {
    matrix::runtime().spawn(async move {
        loop {
            let Some(client) = matrix::CLIENT.lock().unwrap().clone() else {
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                continue;
            };

            let stream = client.sync_stream(matrix::stream_sync_settings()).await;
            pin_mut!(stream);

            while let Some(result) = stream.next().await {
                match result {
                    Ok(_) => {
                        let _ = sink.add(SyncEvent {
                            kind: "rooms_updated".to_string(),
                            room_id: String::new(),
                            body: String::new(),
                        });
                    }
                    Err(_) => break,
                }
            }
        }
    });

    Ok(())
}
