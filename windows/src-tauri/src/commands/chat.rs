use tauri::State;

use crate::chat::{self, Chat, ChatContext, ChatReply};
use crate::shared::Shared;

/// One chat turn. The API key and any file bytes stay on the Rust side.
#[tauri::command]
pub(crate) async fn chat_send(
    shared: State<'_, Shared>,
    chat: State<'_, Chat>,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let (model, llm_provider) = {
        let settings = shared.settings.lock().unwrap();
        (settings.model.clone(), settings.llm_provider.clone())
    };
    chat::send(&chat, &model, &llm_provider, query, context).await
}

#[tauri::command]
pub(crate) fn chat_reset(chat: State<Chat>) {
    chat.reset();
}

/// The provider registry, for the Settings dropdown. Static data only — no
/// secrets cross the IPC boundary.
#[tauri::command]
pub(crate) fn chat_providers() -> Vec<ProviderInfo> {
    crate::providers::PROVIDERS
        .iter()
        .map(|p| ProviderInfo {
            id: p.id.to_string(),
            name: p.name.to_string(),
            key_hint: p.key_hint.to_string(),
            requires_api_key: p.requires_api_key(),
            credential_key: p.credential_key.map(str::to_string),
            url_key: p.url_key.map(str::to_string),
            web_search: p.web_search,
            models: p
                .models
                .iter()
                .map(|(id, label)| ModelInfo {
                    id: id.to_string(),
                    label: label.to_string(),
                })
                .collect(),
        })
        .collect()
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProviderInfo {
    pub id: String,
    pub name: String,
    pub key_hint: String,
    pub requires_api_key: bool,
    pub credential_key: Option<String>,
    pub url_key: Option<String>,
    pub web_search: bool,
    pub models: Vec<ModelInfo>,
}

#[derive(serde::Serialize)]
pub(crate) struct ModelInfo {
    pub id: String,
    pub label: String,
}
