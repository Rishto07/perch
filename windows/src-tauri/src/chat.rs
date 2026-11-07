// LLM chat client — every provider Perch can talk to.
//
// Anthropic (Claude) speaks /v1/messages with web_search and server-side
// fallback models; everything else speaks the OpenAI-compatible
// /v1/chat/completions shape, which Gemini, Mistral, Groq, OpenRouter and
// Ollama's own server all support — one code path for all of them.
//
// The provider is chosen in Settings → Chat provider — never in this file.
// Everything here is driven by the provider registry in providers.rs.

use std::collections::HashMap;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::providers::{lookup, ProviderDef};
use crate::secrets;

const MAX_TOKENS: u32 = 4096;
/// Text and code files are inlined; anything larger is skipped, as on macOS.
const MAX_INLINE_TEXT: u64 = 200_000;

const SYSTEM_PROMPT: &str = "You are Pip, a personal AI assistant perched at the top of the user's screen. \
You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.";

#[derive(Default)]
pub struct Chat {
    /// Conversation history per provider. The Anthropic and OpenAI message
    /// shapes are not interchangeable, so we keep one history per provider
    /// instead of trying to convert between them.
    messages: Mutex<HashMap<String, Vec<Value>>>,
}

impl Chat {
    pub fn reset(&self) {
        self.messages.lock().unwrap().clear();
    }

    fn is_empty(&self, provider: &str) -> bool {
        self.messages
            .lock()
            .unwrap()
            .get(provider)
            .is_none_or(|m| m.is_empty())
    }

    fn push(&self, provider: &str, message: Value) {
        self.messages
            .lock()
            .unwrap()
            .entry(provider.to_string())
            .or_default()
            .push(message);
    }

    fn pop(&self, provider: &str) {
        self.messages
            .lock()
            .unwrap()
            .entry(provider.to_string())
            .or_default()
            .pop();
    }

    fn snapshot(&self, provider: &str) -> Vec<Value> {
        self.messages
            .lock()
            .unwrap()
            .get(provider)
            .cloned()
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ChatContext {
    File {
        name: String,
        path: String,
    },
    Window {
        app_name: String,
        title: String,
        url: Option<String>,
    },
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatReply {
    pub text: String,
}

/// One chat turn. Returns the assistant's text, or a message the island shows
/// in the note view.
pub async fn send(
    chat: &Chat,
    model: &str,
    llm_provider: &str,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let provider = lookup(llm_provider);
    // A model left over from another provider would be rejected by the API —
    // fall back to this provider's default (Ollama users may name any model).
    let model = if provider.id == "ollama" || provider.models.iter().any(|(id, _)| *id == model) {
        model
    } else {
        provider.default_model()
    };
    match provider.id {
        "anthropic" => send_anthropic(chat, model, query, context).await,
        _ => send_openai_compatible(chat, provider, model, query, context).await,
    }
}

// ─── Anthropic ───────────────────────────────────────────────────────────────

const ANTHROPIC_ENDPOINT: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";
/// Server-side fallback: on a policy decline the API retries the same request on
/// a fallback model inside the same call, so the island never shows a dead end.
const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";

async fn send_anthropic(
    chat: &Chat,
    model: &str,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let key = secrets::get("anthropic-api-key")
        .ok_or_else(|| "Claude API key missing. Open settings.".to_string())?;

    let mut content: Vec<Value> = Vec::new();

    if chat.is_empty("anthropic") {
        match &context {
            Some(ChatContext::File { name, path }) => {
                if let Some(block) = file_block(path) {
                    content.push(block);
                }
                content.push(json!({ "type": "text", "text": format!("File: {name}") }));
            }
            Some(ChatContext::Window {
                app_name,
                title,
                url,
            }) => {
                let mut text = format!("Context — App: {app_name}, Window: {title}");
                if let Some(url) = url {
                    text.push_str(&format!(", URL: {url}"));
                }
                content.push(json!({ "type": "text", "text": text }));
            }
            None => {}
        }
    }
    content.push(json!({ "type": "text", "text": query }));

    chat.push("anthropic", json!({ "role": "user", "content": content }));

    let body = json!({
        "model": model,
        "max_tokens": MAX_TOKENS,
        "system": SYSTEM_PROMPT,
        "tools": [{ "type": "web_search_20260209", "name": "web_search", "max_uses": 5 }],
        "fallbacks": "default",
        "messages": chat.snapshot("anthropic"),
    });

    let response = match call_anthropic(&key, &body).await {
        Ok(v) => v,
        Err(err) => {
            chat.pop("anthropic");
            return Err(err);
        }
    };

    if response.get("stop_reason").and_then(Value::as_str) == Some("refusal") {
        chat.pop("anthropic");
        let why = response
            .get("stop_details")
            .and_then(|d| d.get("explanation"))
            .and_then(Value::as_str)
            .unwrap_or("Claude declined this one.");
        return Err(why.to_string());
    }

    let Some(blocks) = response.get("content").and_then(Value::as_array).cloned() else {
        chat.pop("anthropic");
        return Err("Unexpected API response.".into());
    };

    chat.push(
        "anthropic",
        json!({ "role": "assistant", "content": blocks.clone() }),
    );

    let text = blocks
        .iter()
        .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
        .filter_map(|b| b.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string();

    if text.is_empty() {
        return Err("No response text.".into());
    }
    Ok(ChatReply { text })
}

async fn call_anthropic(key: &str, body: &Value) -> Result<Value, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(90))
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .post(ANTHROPIC_ENDPOINT)
        .header("x-api-key", key)
        .header("anthropic-version", ANTHROPIC_VERSION)
        .header("anthropic-beta", FALLBACK_BETA)
        .header("content-type", "application/json")
        .json(body)
        .send()
        .await
        .map_err(|e| format!("Network error: {e}"))?;

    let status = response.status();
    let text = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!("Claude API {status}: {}", error_detail(&text)));
    }
    serde_json::from_str(&text).map_err(|e| format!("Bad API response: {e}"))
}

// ─── OpenAI-compatible (OpenAI, Gemini, Mistral, Groq, OpenRouter, Ollama) ───

async fn send_openai_compatible(
    chat: &Chat,
    provider: &'static ProviderDef,
    model: &str,
    query: String,
    context: Option<ChatContext>,
) -> Result<ChatReply, String> {
    let key = provider
        .credential_key
        .and_then(secrets::get)
        .filter(|k| !k.is_empty());
    // Ollama may run without a key; every hosted provider needs one.
    if provider.credential_key.is_some() && key.is_none() {
        return Err(format!("{} API key missing. Open settings.", provider.name));
    }

    let mut history = chat.snapshot(provider.id);
    if history.is_empty() {
        if let Some(messages) = context_messages(provider, &context) {
            // Context attaches once, like on Claude. The context messages do
            // not contain the question itself — that's pushed next.
            history.extend(messages);
        }
    }
    history.push(json!({ "role": "user", "content": query }));

    // Push before the call so a network error still lands the question in
    // history; pop on failure to keep it consistent.
    chat.push(provider.id, json!({ "role": "user", "content": query }));

    let mut messages = vec![json!({ "role": "system", "content": SYSTEM_PROMPT })];
    messages.extend(history.clone());

    let mut body = json!({
        "model": model,
        "max_tokens": MAX_TOKENS,
        "messages": messages,
    });
    if provider.id == "openrouter" {
        body["http_referrer"] = json!("https://github.com/rishto07/perch");
    }

    let response = match call_openai_compatible(provider, key.as_deref(), &body).await {
        Ok(v) => v,
        Err(err) => {
            chat.pop(provider.id);
            return Err(err);
        }
    };

    let Some(choice) = response
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|c| c.first())
    else {
        chat.pop(provider.id);
        return Err("Unexpected API response.".into());
    };

    let Some(message) = choice.get("message") else {
        chat.pop(provider.id);
        return Err("Unexpected API response.".into());
    };

    let text = message
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();

    if text.is_empty() {
        chat.pop(provider.id);
        return Err("No response text.".into());
    }

    chat.push(provider.id, message.clone());
    Ok(ChatReply { text })
}

/// Build the context messages for the first turn. Images travel as base64
/// data URIs; PDFs only work on Claude.
fn context_messages(
    provider: &'static ProviderDef,
    context: &Option<ChatContext>,
) -> Option<Vec<Value>> {
    match context {
        Some(ChatContext::File { name, path }) => {
            let mut parts = Vec::new();
            if let Some(ext) = std::path::Path::new(path)
                .extension()
                .and_then(|e| e.to_str())
            {
                match ext.to_lowercase().as_str() {
                    "pdf" => {
                        parts.push(json!({
                            "type": "text",
                            "text": format!("File: {name} — PDFs can't be attached on {}; ask me to read the text instead.", provider.name),
                        }));
                    }
                    "jpg" | "jpeg" | "png" | "gif" | "webp" => {
                        if let Ok(bytes) = std::fs::read(path) {
                            let media = match ext.to_lowercase().as_str() {
                                "jpg" | "jpeg" => "image/jpeg",
                                "png" => "image/png",
                                "gif" => "image/gif",
                                _ => "image/webp",
                            };
                            parts.push(json!({
                                "type": "image_url",
                                "image_url": {
                                    "url": format!("data:{media};base64,{}", base64(&bytes)),
                                },
                            }));
                        }
                    }
                    _ => {
                        if std::fs::metadata(path)
                            .map(|m| m.len() <= MAX_INLINE_TEXT)
                            .unwrap_or(false)
                        {
                            if let Ok(text) = std::fs::read_to_string(path) {
                                parts.push(json!({
                                    "type": "text",
                                    "text": format!("File contents of {name}:\n{text}"),
                                }));
                            }
                        }
                    }
                }
            }
            if parts.is_empty() {
                return Some(vec![json!({
                    "role": "user",
                    "content": format!("File: {name} (couldn't be read)"),
                })]);
            }
            Some(vec![
                json!({ "role": "user", "content": Value::Array(parts) }),
            ])
        }
        Some(ChatContext::Window {
            app_name,
            title,
            url,
        }) => {
            let mut text = format!("Context — App: {app_name}, Window: {title}");
            if let Some(url) = url {
                text.push_str(&format!(", URL: {url}"));
            }
            Some(vec![json!({ "role": "user", "content": text })])
        }
        None => None,
    }
}

async fn call_openai_compatible(
    provider: &'static ProviderDef,
    key: Option<&str>,
    body: &Value,
) -> Result<Value, String> {
    let base = provider.base_url();
    if base.is_empty() {
        return Err(format!("{} endpoint is not configured.", provider.name));
    }
    let url = format!("{base}/chat/completions");

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(90))
        .build()
        .map_err(|e| e.to_string())?;

    let mut req = client
        .post(&url)
        .header("content-type", "application/json")
        .json(body);
    if let Some(k) = key {
        req = req.header("authorization", format!("Bearer {k}"));
    }
    if provider.id == "openrouter" {
        req = req
            .header("http-referer", "https://github.com/rishto07/perch")
            .header("x-title", "Perch");
    }

    let response = req
        .send()
        .await
        .map_err(|e| format!("Network error: {e}"))?;
    let status = response.status();
    let text = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!(
            "{} API {status}: {}",
            provider.name,
            error_detail(&text)
        ));
    }
    serde_json::from_str(&text).map_err(|e| format!("Bad API response: {e}"))
}

/// Pull the human-readable message out of either Anthropic- or OpenAI-shaped
/// errors.
fn error_detail(text: &str) -> String {
    serde_json::from_str::<Value>(text)
        .ok()
        .and_then(|v| {
            v.get("error")
                .and_then(|e| e.get("message"))
                .or_else(|| v.get("message"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .unwrap_or_else(|| text.chars().take(200).collect())
}

/// Text and code files are inlined; PDFs and images travel as base64 blocks.
fn file_block(path: &str) -> Option<Value> {
    let ext = std::path::Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    let media_type = match ext.as_str() {
        "pdf" => Some(("document", "application/pdf")),
        "jpg" | "jpeg" => Some(("image", "image/jpeg")),
        "png" => Some(("image", "image/png")),
        "gif" => Some(("image", "image/gif")),
        "webp" => Some(("image", "image/webp")),
        _ => None,
    };

    if let Some((block_type, media)) = media_type {
        let bytes = std::fs::read(path).ok()?;
        return Some(json!({
            "type": block_type,
            "source": { "type": "base64", "media_type": media, "data": base64(&bytes) },
        }));
    }

    let len = std::fs::metadata(path).ok()?.len();
    if len > MAX_INLINE_TEXT {
        return None;
    }
    let text = std::fs::read_to_string(path).ok()?;
    Some(json!({ "type": "text", "text": format!("File contents:\n{text}") }))
}

/// Small standalone base64 encoder — not worth another dependency.
/// Also used for Stripe's basic auth.
pub(crate) fn base64_for(bytes: &[u8]) -> String {
    base64(bytes)
}

fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            TABLE[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::base64;

    #[test]
    fn base64_matches_rfc4648_vectors() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foob"), "Zm9vYg==");
        assert_eq!(base64(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }
}
