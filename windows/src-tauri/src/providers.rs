// LLM providers for the island chat.
//
// One switch (Settings → Chat provider) picks which model answers "Ask anything".
// Anthropic speaks /v1/messages with web_search; the rest speak the
// OpenAI-compatible /v1/chat/completions shape, which OpenAI, Google Gemini
// (OpenAI-compatible endpoint), Mistral, Groq, OpenRouter and Ollama all
// support — so there is a single code path for all of them.
//
// Everything is data: id, name, base URL, model list and credential key. Adding
// a provider is a new entry here, no other code changes.

#[derive(Debug, Clone, Copy)]
pub struct ProviderDef {
    /// Stable id stored in settings.json (never rename).
    pub id: &'static str,
    pub name: &'static str,
    /// Hint shown in Settings next to the key field.
    pub key_hint: &'static str,
    /// Base URL for the OpenAI-compatible endpoint.
    /// `None` for Anthropic, which has its own /v1/messages path in chat.rs.
    pub base_url: Option<&'static str>,
    /// Credential Manager key, or `None` for Ollama (no key by default).
    pub credential_key: Option<&'static str>,
    /// URL the user can override (Ollama instance).
    pub url_key: Option<&'static str>,
    /// Models offered in the dropdown, (id, label).
    pub models: &'static [(&'static str, &'static str)],
    /// Web search + developer features are Anthropic-only for now.
    pub web_search: bool,
}

pub const PROVIDERS: &[ProviderDef] = &[
    ProviderDef {
        id: "anthropic",
        name: "Claude",
        key_hint: "sk-ant-…",
        base_url: None,
        credential_key: Some("anthropic-api-key"),
        url_key: None,
        models: &[
            ("claude-opus-5", "Claude Opus 5"),
            ("claude-sonnet-5", "Claude Sonnet 5"),
            ("claude-haiku-4-5", "Claude Haiku 4.5"),
        ],
        web_search: true,
    },
    ProviderDef {
        id: "openai",
        name: "OpenAI",
        key_hint: "sk-…",
        base_url: Some("https://api.openai.com/v1"),
        credential_key: Some("openai-api-key"),
        url_key: None,
        models: &[
            ("gpt-5", "GPT-5"),
            ("gpt-5-mini", "GPT-5 mini"),
            ("gpt-4.1", "GPT-4.1"),
            ("gpt-4.1-mini", "GPT-4.1 mini"),
            ("o4-mini", "o4-mini"),
        ],
        web_search: false,
    },
    ProviderDef {
        id: "gemini",
        name: "Google Gemini",
        key_hint: "AIza…",
        base_url: Some("https://generativelanguage.googleapis.com/v1beta/openai"),
        credential_key: Some("gemini-api-key"),
        url_key: None,
        models: &[
            ("gemini-2.5-pro", "Gemini 2.5 Pro"),
            ("gemini-2.5-flash", "Gemini 2.5 Flash"),
            ("gemini-2.0-flash", "Gemini 2.0 Flash"),
        ],
        web_search: false,
    },
    ProviderDef {
        id: "mistral",
        name: "Mistral",
        key_hint: "…",
        base_url: Some("https://api.mistral.ai/v1"),
        credential_key: Some("mistral-api-key"),
        url_key: None,
        models: &[
            ("mistral-large-latest", "Mistral Large"),
            ("mistral-medium-latest", "Mistral Medium"),
            ("codestral-latest", "Codestral"),
        ],
        web_search: false,
    },
    ProviderDef {
        id: "groq",
        name: "Groq",
        key_hint: "gsk_…",
        base_url: Some("https://api.groq.com/openai/v1"),
        credential_key: Some("groq-api-key"),
        url_key: None,
        models: &[
            ("llama-3.3-70b-versatile", "Llama 3.3 70B"),
            ("llama-3.1-8b-instant", "Llama 3.1 8B"),
            ("qwen/qwen3-32b", "Qwen3 32B"),
        ],
        web_search: false,
    },
    ProviderDef {
        id: "openrouter",
        name: "OpenRouter (all models)",
        key_hint: "sk-or-…",
        base_url: Some("https://openrouter.ai/api/v1"),
        credential_key: Some("openrouter-api-key"),
        url_key: None,
        models: &[
            ("openrouter/auto", "OpenRouter Auto"),
            ("openai/gpt-5", "GPT-5"),
            ("anthropic/claude-sonnet-5", "Claude Sonnet 5"),
            ("google/gemini-2.5-pro", "Gemini 2.5 Pro"),
            ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B"),
            ("deepseek/deepseek-chat", "DeepSeek Chat"),
        ],
        web_search: false,
    },
    ProviderDef {
        id: "ollama",
        name: "Ollama (local)",
        key_hint: "no key needed",
        base_url: Some("http://localhost:11434/v1"),
        credential_key: None,
        url_key: Some("ollama-url"),
        models: &[
            ("llama3.3", "Llama 3.3"),
            ("mistral", "Mistral"),
            ("qwen2.5-coder", "Qwen2.5 Coder"),
            ("deepseek-r1", "DeepSeek R1"),
        ],
        web_search: false,
    },
];

/// Look up a provider by the id stored in settings. Defaults to Claude.
pub fn lookup(id: &str) -> &'static ProviderDef {
    PROVIDERS
        .iter()
        .find(|p| p.id == id)
        .unwrap_or(&PROVIDERS[0])
}

impl ProviderDef {
    pub fn id(&self) -> &'static str {
        self.id
    }

    pub fn default_model(&self) -> &'static str {
        self.models[0].0
    }

    pub fn requires_api_key(&self) -> bool {
        self.credential_key.is_some()
    }

    /// Base URL for OpenAI-compatible requests. Ollama honours the `ollama-url`
    /// override when set.
    pub fn base_url(&self) -> String {
        match self.url_key.and_then(crate::secrets::get) {
            Some(url) if !url.trim().is_empty() => {
                let url = url.trim().trim_end_matches('/').to_string();
                if url.ends_with("/v1") {
                    url
                } else {
                    format!("{url}/v1")
                }
            }
            _ => self.base_url.unwrap_or("").to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_provider_has_unique_id_and_models() {
        let mut ids = std::collections::HashSet::new();
        for p in PROVIDERS {
            assert!(ids.insert(p.id), "duplicate provider id {}", p.id);
            assert!(!p.models.is_empty(), "{} needs at least one model", p.id);
        }
    }

    #[test]
    fn ollama_does_not_require_a_key() {
        let ollama = lookup("ollama");
        assert!(ollama.credential_key.is_none());
        assert_eq!(ollama.url_key.as_deref(), Some("ollama-url"));
    }

    #[test]
    fn unknown_id_falls_back_to_claude() {
        assert_eq!(lookup("nope").id(), "anthropic");
    }

    #[test]
    fn every_other_provider_needs_a_key() {
        for p in PROVIDERS {
            if p.id == "ollama" {
                continue;
            }
            assert!(
                p.credential_key.is_some(),
                "{} needs a credential key",
                p.id
            );
        }
    }
}
