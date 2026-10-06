use std::sync::Mutex;

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    config::SyncSettings,
    room::reply::{EnforceThread, Reply},
    ruma::{
        events::{
            room::message::{
                AddMentions, Relation, RoomMessageEventContent, RoomMessageEventContentWithoutRelation,
            },
            AnySyncMessageLikeEvent, AnySyncTimelineEvent,
        },
        EventId, RoomId,
    },
    Client,
};
use once_cell::sync::Lazy;

use crate::models::{Message, RoomInfo, SessionInfo};

pub static CLIENT: Lazy<Mutex<Option<Client>>> = Lazy::new(|| Mutex::new(None));

pub fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: Lazy<tokio::runtime::Runtime> =
        Lazy::new(|| tokio::runtime::Runtime::new().expect("failed to create tokio runtime"));
    &RT
}

fn with_client() -> Result<Client> {
    CLIENT
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| anyhow!("no active session"))
}

async fn build_client(homeserver: &str, store_path: &str) -> Result<Client> {
    let client = Client::builder()
        .homeserver_url(homeserver)
        .sqlite_store(store_path, None)
        .build()
        .await
        .context("failed to build client")?;
    client
        .event_cache()
        .subscribe()
        .context("failed to subscribe event cache")?;
    Ok(client)
}

fn save_session(client: &Client, session_path: &str) -> Result<()> {
    let session = client
        .matrix_auth()
        .session()
        .ok_or_else(|| anyhow!("no session available after login"))?;
    let json = serde_json::to_string(&session)?;
    std::fs::write(session_path, json)?;
    Ok(())
}

pub async fn login(
    homeserver: String,
    username: String,
    password: String,
    store_path: String,
    session_path: String,
) -> Result<SessionInfo> {
    let client = build_client(&homeserver, &store_path).await?;
    client
        .matrix_auth()
        .login_username(&username, &password)
        .send()
        .await
        .context("login failed")?;

    save_session(&client, &session_path)?;

    let info = SessionInfo {
        user_id: client
            .user_id()
            .map(|u| u.to_string())
            .unwrap_or_default(),
        display_name: username,
    };

    *CLIENT.lock().unwrap() = Some(client);
    Ok(info)
}

pub async fn restore_session(
    homeserver: String,
    store_path: String,
    session_path: String,
) -> Result<SessionInfo> {
    let client = build_client(&homeserver, &store_path).await?;
    let json = std::fs::read_to_string(&session_path).context("no saved session found")?;
    let session: MatrixSession = serde_json::from_str(&json).context("invalid session file")?;
    client
        .restore_session(session)
        .await
        .context("failed to restore session")?;

    let info = SessionInfo {
        user_id: client
            .user_id()
            .map(|u| u.to_string())
            .unwrap_or_default(),
        display_name: String::new(),
    };

    *CLIENT.lock().unwrap() = Some(client);
    Ok(info)
}

pub fn stream_sync_settings() -> SyncSettings {
    SyncSettings::new().ignore_timeout_on_first_sync(true)
}

async fn room_name(room: &matrix_sdk::Room) -> String {
    use matrix_sdk::ruma::events::room::name::RoomNameEventContent;

    if let Ok(Some(raw)) = room.get_state_event_static::<RoomNameEventContent>().await {
        if let Ok(state) = raw.deserialize() {
            if let Some(sync) = state.as_sync() {
                if let Some(original) = sync.as_original() {
                    if !original.content.name.is_empty() {
                        return original.content.name.clone();
                    }
                }
            }
        }
    }

    if let Some(alias) = room.canonical_alias() {
        return alias.to_string();
    }

    if let Ok(members) = room
        .members_no_sync(matrix_sdk::RoomMemberships::JOIN)
        .await
    {
        let others: Vec<_> = members.iter().filter(|m| !m.is_account_user()).collect();
        if others.len() == 1 {
            return others[0].name().to_string();
        }
    }

    room.room_id().to_string()
}

pub async fn list_rooms() -> Result<Vec<RoomInfo>> {
    let client = with_client()?;
    let mut rooms = Vec::new();
    for room in client.joined_rooms() {
        let room_id = room.room_id().to_string();
        let name = room_name(&room).await;
        rooms.push(RoomInfo { room_id, name });
    }
    rooms.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(rooms)
}

pub async fn get_messages(room_id: String) -> Result<Vec<Message>> {
    use std::collections::HashMap;

    let client = with_client()?;
    let room_id = RoomId::parse(&room_id).context("invalid room id")?;
    let _room = client
        .get_room(&room_id)
        .ok_or_else(|| anyhow!("room not found"))?;

    let (room_event_cache, _drop_handles) = client.event_cache().room(&room_id).await?;

    let events = room_event_cache.events().await?;

    // Resolve o texto das mensagens citadas (para exibir replies).
    let mut body_by_id: HashMap<String, String> = HashMap::new();
    for event in &events {
        let Ok(timeline_event) = event.raw().deserialize() else {
            continue;
        };
        let AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(msg)) =
            timeline_event
        else {
            continue;
        };
        let Some(original) = msg.as_original() else {
            continue;
        };
        if let Some(id) = event.event_id() {
            body_by_id.insert(id.to_string(), original.content.body().to_string());
        }
    }

    let mut messages = Vec::new();
    for event in &events {
        let Ok(timeline_event) = event.raw().deserialize() else {
            continue;
        };
        let AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(msg)) =
            timeline_event
        else {
            continue;
        };
        let Some(original) = msg.as_original() else {
            continue;
        };

        let mut reply_to_event_id = String::new();
        let mut reply_to_body = String::new();
        if let Some(Relation::Reply(reply)) = &original.content.relates_to {
            let id = reply.in_reply_to.event_id.to_string();
            reply_to_event_id = id.clone();
            if let Some(body) = body_by_id.get(&id) {
                reply_to_body = body.clone();
            }
        }

        messages.push(Message {
            event_id: event
                .event_id()
                .map(|e| e.to_string())
                .unwrap_or_default(),
            sender: event.sender().map(|s| s.to_string()).unwrap_or_default(),
            body: original.content.body().to_string(),
            timestamp_millis: event.timestamp().map(|t| i64::from(t.get())).unwrap_or(0),
            reply_to_event_id,
            reply_to_body,
        });
    }
    messages.reverse();
    Ok(messages)
}

pub async fn send_message(
    room_id: String,
    text: String,
    reply_to_event_id: Option<String>,
) -> Result<()> {
    let client = with_client()?;
    let room_id = RoomId::parse(&room_id).context("invalid room id")?;
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| anyhow!("room not found"))?;

    let event_content = if let Some(reply_to) = reply_to_event_id {
        let reply_to_id = EventId::parse(&reply_to).context("invalid reply event id")?;
        let reply = Reply {
            event_id: reply_to_id,
            enforce_thread: EnforceThread::Unthreaded,
            add_mentions: AddMentions::Yes,
        };
        room.make_reply_event(RoomMessageEventContentWithoutRelation::text_plain(text), reply)
            .await
            .context("failed to build reply")?
    } else {
        RoomMessageEventContent::text_plain(text)
    };

    room.send(event_content)
        .await
        .context("failed to send message")?;
    Ok(())
}

pub async fn logout(session_path: String) -> Result<()> {
    let client = CLIENT.lock().unwrap().take();
    if let Some(client) = client {
        let _ = client.matrix_auth().logout().await;
    }
    let _ = std::fs::remove_file(session_path);
    Ok(())
}
