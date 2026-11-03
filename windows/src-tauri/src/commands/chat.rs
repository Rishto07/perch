use tauri::State;

use crate::claude::{self, Chat, ChatContext, ChatReply};
use crate::shared::Shared;

/// One chat turn. The API key and any file bytes stay on the Rust side.
#[tauri::command]
pub(crate) async fn chat_send(
    shared: State<'_, Shared>,
    chat: State<'_, Chat>,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let model = shared.settings.lock().unwrap().model.clone();
    claude::send(&chat, &model, query, context).await
}

#[tauri::command]
pub(crate) fn chat_reset(chat: State<Chat>) {
    chat.reset();
}
