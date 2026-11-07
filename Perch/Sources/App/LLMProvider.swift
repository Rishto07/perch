import Foundation

/// One chat provider. The same registry exists in the Windows app
/// (`src-tauri/src/providers.rs`) — keep ids, names and model ids in sync.
///
/// Anthropic speaks `/v1/messages` with web search; every other provider speaks
/// the OpenAI-compatible `/v1/chat/completions` shape, so one code path covers
/// OpenAI, Gemini, Mistral, Groq, OpenRouter and Ollama.
struct LLMProvider: Identifiable, Equatable, Sendable {
    struct Model: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
    }

    /// Stable id stored in UserDefaults — never rename.
    let id: String
    let name: String
    /// Hint shown as the key field's placeholder.
    let keyHint: String
    /// OpenAI-compatible base URL (`nil` for Anthropic).
    let baseURL: String?
    /// Keychain key for the API key (`nil` for Ollama).
    let credentialKey: String?
    /// Keychain key for an editable endpoint (Ollama only).
    let urlKey: String?
    let models: [Model]
    /// Web search and the server-side fallback are Anthropic-only for now.
    let webSearch: Bool

    var defaultModel: String { models[0].id }
    var needsKey: Bool { credentialKey != nil }

    func offers(_ model: String) -> Bool {
        models.contains { $0.id == model }
    }

    /// Base URL for OpenAI-compatible requests, honouring the Ollama override.
    func resolvedBaseURL() -> String? {
        if let urlKey, let raw = KeychainStore.shared.get(urlKey) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
                return base.hasSuffix("/v1") ? base : base + "/v1"
            }
        }
        return baseURL
    }

    static let all: [LLMProvider] = [
        LLMProvider(
            id: "anthropic", name: "Claude", keyHint: "sk-ant-…",
            baseURL: nil, credentialKey: "anthropic-api-key", urlKey: nil,
            models: [
                Model(id: "claude-opus-5", label: "Claude Opus 5"),
                Model(id: "claude-sonnet-5", label: "Claude Sonnet 5"),
                Model(id: "claude-haiku-4-5", label: "Claude Haiku 4.5"),
            ],
            webSearch: true
        ),
        LLMProvider(
            id: "openai", name: "OpenAI", keyHint: "sk-…",
            baseURL: "https://api.openai.com/v1", credentialKey: "openai-api-key", urlKey: nil,
            models: [
                Model(id: "gpt-5", label: "GPT-5"),
                Model(id: "gpt-5-mini", label: "GPT-5 mini"),
                Model(id: "gpt-4.1", label: "GPT-4.1"),
                Model(id: "gpt-4.1-mini", label: "GPT-4.1 mini"),
                Model(id: "o4-mini", label: "o4-mini"),
            ],
            webSearch: false
        ),
        LLMProvider(
            id: "gemini", name: "Google Gemini", keyHint: "AIza…",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            credentialKey: "gemini-api-key", urlKey: nil,
            models: [
                Model(id: "gemini-2.5-pro", label: "Gemini 2.5 Pro"),
                Model(id: "gemini-2.5-flash", label: "Gemini 2.5 Flash"),
                Model(id: "gemini-2.0-flash", label: "Gemini 2.0 Flash"),
            ],
            webSearch: false
        ),
        LLMProvider(
            id: "mistral", name: "Mistral", keyHint: "…",
            baseURL: "https://api.mistral.ai/v1", credentialKey: "mistral-api-key", urlKey: nil,
            models: [
                Model(id: "mistral-large-latest", label: "Mistral Large"),
                Model(id: "mistral-medium-latest", label: "Mistral Medium"),
                Model(id: "codestral-latest", label: "Codestral"),
            ],
            webSearch: false
        ),
        LLMProvider(
            id: "groq", name: "Groq", keyHint: "gsk_…",
            baseURL: "https://api.groq.com/openai/v1", credentialKey: "groq-api-key", urlKey: nil,
            models: [
                Model(id: "llama-3.3-70b-versatile", label: "Llama 3.3 70B"),
                Model(id: "llama-3.1-8b-instant", label: "Llama 3.1 8B"),
                Model(id: "qwen/qwen3-32b", label: "Qwen3 32B"),
            ],
            webSearch: false
        ),
        LLMProvider(
            id: "openrouter", name: "OpenRouter (all models)", keyHint: "sk-or-…",
            baseURL: "https://openrouter.ai/api/v1", credentialKey: "openrouter-api-key", urlKey: nil,
            models: [
                Model(id: "openrouter/auto", label: "OpenRouter Auto"),
                Model(id: "openai/gpt-5", label: "GPT-5"),
                Model(id: "anthropic/claude-sonnet-5", label: "Claude Sonnet 5"),
                Model(id: "google/gemini-2.5-pro", label: "Gemini 2.5 Pro"),
                Model(id: "meta-llama/llama-3.3-70b-instruct", label: "Llama 3.3 70B"),
                Model(id: "deepseek/deepseek-chat", label: "DeepSeek Chat"),
            ],
            webSearch: false
        ),
        LLMProvider(
            id: "ollama", name: "Ollama (local)", keyHint: "no key needed",
            baseURL: "http://localhost:11434/v1", credentialKey: nil,
            urlKey: "ollama-url",
            models: [
                Model(id: "llama3.3", label: "Llama 3.3"),
                Model(id: "mistral", label: "Mistral"),
                Model(id: "qwen2.5-coder", label: "Qwen2.5 Coder"),
                Model(id: "deepseek-r1", label: "DeepSeek R1"),
            ],
            webSearch: false
        ),
    ]

    static let fallback = all[0]

    static func lookup(_ id: String) -> LLMProvider {
        all.first { $0.id == id } ?? fallback
    }
}
