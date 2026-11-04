import Foundation
import Security

// MARK: - Keychain helpers

enum Keychain {
    static let service = "com.perch.Perch"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete existing item first (update pattern)
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(lookup as CFDictionary)
        // Add with strictest access control:
        // WhenUnlockedThisDeviceOnly = accessible only while Mac is unlocked,
        // never synced to iCloud, never migrated to another device.
        let item: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain cache (reads each key ONCE at launch; all subsequent access via dict)

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private static let allKeys = [
        "anthropic-api-key",
        "openai-api-key",
        "gemini-api-key",
        "mistral-api-key",
        "groq-api-key",
        "openrouter-api-key",
        "ollama-url",
        "resend-api-key", "resend-from",
        "n8n-url", "n8n-api-key",
        "vercel-token",
        "github-token",
        "stripe-api-key",
        "calcom-api-key",
        "notion-api-key",
    ]

    private init() {
        // Called once, on main thread (AppDelegate triggers shared at launch).
        for key in Self.allKeys {
            if let v = Keychain.load(key: key) { cache[key] = v }
        }
    }

    /// Thread-safe read — never touches the Keychain.
    func get(_ key: String) -> String? {
        lock.withLock { cache[key] }
    }

    /// Updates cache + persists to Keychain.
    func set(_ key: String, value: String) {
        lock.withLock { cache[key] = value }
        Keychain.save(key: key, value: value)
    }

    /// Removes from cache + Keychain only if the key was previously set.
    func remove(_ key: String) {
        let had = lock.withLock { () -> Bool in
            let exists = cache[key] != nil
            cache[key] = nil
            return exists
        }
        if had { Keychain.delete(key: key) }
    }
}

// MARK: - Chat client

/// Every provider Perch can talk to. Anthropic keeps its own `/v1/messages`
/// shape with web search; the rest share the OpenAI-compatible
/// `/v1/chat/completions` path. The provider is chosen in Settings, never here.
@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"

    var apiKey: String? { KeychainStore.shared.get("anthropic-api-key") }

    /// One conversation per provider — the Anthropic and OpenAI message shapes
    /// are not interchangeable, so switching providers starts a fresh thread
    /// instead of translating history.
    private var conversations: [String: [[String: Any]]] = [:]

    func clearConversation() {
        conversations.removeAll()
    }

    private let systemPrompt = """
    You are Pip, a personal AI assistant perched at the top of the user's screen. \
    You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
    Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
    No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.
    """

    private let structuredSystemPrompt = """
    You are an assistant built into the notch of a Mac. Reply in English, short and precise.
    Reply ONLY with valid JSON in this exact format:
    {"title":"...","items":[{"label":"...","detail":"...","url":"..."}],"note":"..."}
    Maximum 3 items. "url" is optional. "note" is optional.
    """

    private let webSearchTools: [[String: Any]] = [
        ["type": "web_search_20250305", "name": "web_search", "max_uses": 5]
    ]

    // MARK: - Chat (multi-turn, natural text + web search)

    func chat(query: String, context: PromptContext?, state: AppState) async {
        let provider = LLMProvider.lookup(state.llmProvider)
        if provider.id != "anthropic" {
            await openAICompatibleChat(provider: provider, query: query, context: context, state: state)
            return
        }

        guard let key = apiKey, !key.isEmpty else {
            await showError("API key missing. Open settings.", state: state)
            return
        }

        var history = conversations["anthropic"] ?? []

        // Build user content for this turn
        var userContent: [[String: Any]] = []

        // Add file/window context on first message only
        if history.isEmpty, let context = context {
            switch context {
            case .window(let app, let title, let url):
                var text = "Context — App: \(app), Window: \(title)"
                if let url = url { text += ", URL: \(url)" }
                userContent.append(["type": "text", "text": text])
            case .file(let name, let fileURL):
                if let fileURL = fileURL, let block = readFileAsBlock(url: fileURL) {
                    userContent.append(block)
                }
                userContent.append(["type": "text", "text": "File: \(name)"])
            }
        }
        userContent.append(["type": "text", "text": query])

        history.append(["role": "user", "content": userContent])
        conversations["anthropic"] = history

        let body: [String: Any] = [
            "model": state.activeModel,
            "max_tokens": 4096,
            "tools": webSearchTools,
            "system": systemPrompt,
            "messages": history,
        ]

        do {
            let data = try await callAPI(body: body, key: key, beta: "web-search-2025-03-05")
            await handleChatResult(data, state: state)
        } catch {
            conversations["anthropic"]?.removeLast()
            await showError("Network error: \(error.localizedDescription)", state: state)
        }
    }

    // MARK: - Structured search (M8 — window attach + web search)

    func search(query: String, context: PromptContext?, state: AppState) async {
        let provider = LLMProvider.lookup(state.llmProvider)
        if provider.id != "anthropic" {
            await openAICompatibleSearch(provider: provider, query: query, context: context, state: state)
            return
        }

        guard let key = apiKey, !key.isEmpty else {
            await showError("Anthropic API key missing. Open settings to configure it.", state: state)
            return
        }

        var userContent: [[String: Any]] = []
        switch context {
        case .window(let appName, let title, let url):
            var text = "App: \(appName)\nWindow title: \(title)"
            if let url = url { text += "\nURL: \(url)" }
            text += "\n\nRequest: \(query)"
            userContent.append(["type": "text", "text": text])
        case .file(let name, let fileURL):
            if let fileURL = fileURL, let fileBlock = readFileAsBlock(url: fileURL) {
                userContent.append(fileBlock)
            }
            userContent.append(["type": "text", "text": "File: \(name)\n\nRequest: \(query)"])
        case nil:
            userContent.append(["type": "text", "text": query])
        }

        let tools: [[String: Any]] = [
            ["type": "web_search_20250305", "name": "web_search", "max_uses": 3]
        ]

        let body: [String: Any] = [
            "model": state.activeModel,
            "max_tokens": 1024,
            "tools": tools,
            "system": structuredSystemPrompt,
            "messages": [["role": "user", "content": userContent]],
        ]

        do {
            let result = try await callAPI(body: body, key: key, beta: "web-search-2025-03-05")
            await handleResult(result, state: state)
        } catch {
            await showError("Network error: \(error.localizedDescription)", state: state)
        }
    }

    // MARK: - OpenAI-compatible providers (OpenAI, Gemini, Mistral, Groq, OpenRouter, Ollama)

    private func openAICompatibleChat(
        provider: LLMProvider,
        query: String,
        context: PromptContext?,
        state: AppState
    ) async {
        guard let base = provider.resolvedBaseURL() else {
            await showError("\(provider.name) endpoint is not configured.", state: state)
            return
        }
        let key: String?
        if let credentialKey = provider.credentialKey {
            let stored = KeychainStore.shared.get(credentialKey) ?? ""
            guard !stored.isEmpty else {
                await showError("\(provider.name) API key missing. Open settings.", state: state)
                return
            }
            key = stored
        } else {
            key = nil
        }

        var history = conversations[provider.id] ?? []

        if history.isEmpty, let context,
           let first = firstTurnContent(context: context, provider: provider) {
            history.append(["role": "user", "content": first])
        }
        history.append(["role": "user", "content": query])
        conversations[provider.id] = history

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: history)

        let body: [String: Any] = [
            "model": state.activeModel,
            "max_tokens": 4096,
            "messages": messages,
        ]

        do {
            let data = try await callOpenAICompatible(base: base, provider: provider, key: key, body: body)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                conversations[provider.id]?.removeLast()
                await showError("Unexpected API response.", state: state)
                return
            }
            conversations[provider.id]?.append(["role": "assistant", "content": text])
            await finishChat(text: text, state: state)
        } catch {
            conversations[provider.id]?.removeLast()
            await showError("Network error: \(error.localizedDescription)", state: state)
        }
    }

    private func openAICompatibleSearch(
        provider: LLMProvider,
        query: String,
        context: PromptContext?,
        state: AppState
    ) async {
        guard let base = provider.resolvedBaseURL() else {
            await showError("\(provider.name) endpoint is not configured.", state: state)
            return
        }
        let key: String?
        if let credentialKey = provider.credentialKey {
            let stored = KeychainStore.shared.get(credentialKey) ?? ""
            guard !stored.isEmpty else {
                await showError("\(provider.name) API key missing. Open settings.", state: state)
                return
            }
            key = stored
        } else {
            key = nil
        }

        var request = ""
        switch context {
        case .window(let appName, let title, let url):
            request = "App: \(appName)\nWindow title: \(title)"
            if let url = url { request += "\nURL: \(url)" }
            request += "\n\nRequest: \(query)"
        case .file(let name, _):
            request = "File: \(name)\n\nRequest: \(query)"
        case nil:
            request = query
        }

        let body: [String: Any] = [
            "model": state.activeModel,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": structuredSystemPrompt],
                ["role": "user", "content": request],
            ],
        ]

        do {
            let data = try await callOpenAICompatible(base: base, provider: provider, key: key, body: body)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else {
                await showError("Unexpected API response.", state: state)
                return
            }
            await handleStructuredText(text: text, state: state)
        } catch {
            await showError("Network error: \(error.localizedDescription)", state: state)
        }
    }

    /// First-turn context in OpenAI message shape. Images travel as data URIs;
    /// PDFs are Claude-only, so the model is told to ask for the text instead.
    private func firstTurnContent(context: PromptContext, provider: LLMProvider) -> [[String: Any]]? {
        switch context {
        case .window(let app, let title, let url):
            var text = "Context — App: \(app), Window: \(title)"
            if let url = url { text += ", URL: \(url)" }
            return [["type": "text", "text": text]]
        case .file(let name, let fileURL):
            guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
            let ext = fileURL.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
                let media = (ext == "jpg" || ext == "jpeg") ? "image/jpeg" : "image/\(ext)"
                return [
                    ["type": "image_url", "image_url": ["url": "data:\(media);base64,\(data.base64EncodedString())"]],
                    ["type": "text", "text": "File: \(name)"],
                ]
            }
            if ext == "pdf" {
                return [["type": "text", "text": "File: \(name) — PDFs can't be attached on \(provider.name); ask me to read the text instead."]]
            }
            if data.count <= 200_000, let text = String(data: data, encoding: .utf8) {
                return [["type": "text", "text": "File contents of \(name):\n\(text)"]]
            }
            return nil
        }
    }

    // MARK: - API calls

    private func callAPI(body: [String: Any], key: String, beta: String? = nil) async throws -> Data {
        var request = URLRequest(url: anthropicEndpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = errorDetail(data)
            throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    private func callOpenAICompatible(
        base: String,
        provider: LLMProvider,
        key: String?,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: base + "/chat/completions") else {
            throw NSError(domain: "Perch", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid \(provider.name) endpoint."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
        if provider.id == "openrouter" {
            request.setValue("https://github.com/rishto07/perch", forHTTPHeaderField: "http-referer")
            request.setValue("Perch", forHTTPHeaderField: "x-title")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = errorDetail(data)
            throw NSError(domain: provider.name, code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    /// Pull the human-readable message out of either Anthropic- or OpenAI-shaped errors.
    private func errorDetail(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        let raw = String(data: data, encoding: .utf8) ?? "unknown error"
        return String(raw.prefix(200))
    }

    // MARK: - Results

    private func handleChatResult(_ data: Data, state: AppState) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            conversations["anthropic"]?.removeLast()
            await showError("Unexpected API response.", state: state)
            return
        }

        // Store full content (includes tool_use/tool_result blocks) for correct multi-turn context
        conversations["anthropic"]?.append(["role": "assistant", "content": content])

        guard let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String, !text.isEmpty else {
            await showError("No response text.", state: state)
            return
        }

        await finishChat(text: text, state: state)
    }

    private func finishChat(text: String, state: AppState) async {
        state.chatHistory.append(ChatMessage(role: .assistant, content: text.trimmingCharacters(in: .whitespacesAndNewlines)))

        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    private func handleResult(_ data: Data, state: AppState) async {
        // Extract text from Anthropic response (may contain tool_use / web_search_tool_result blocks)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            await showError("Unexpected API response.", state: state)
            return
        }
        await handleStructuredText(text: text, state: state)
    }

    private func handleStructuredText(text: String, state: AppState) async {
        // Strip markdown code fences if present, then extract JSON object
        let cleanText: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            cleanText = String(text[start...end])
        } else {
            cleanText = text
        }

        // Try to parse as our JSON format
        if let resultData = cleanText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            let title  = parsed["title"] as? String ?? "Result"
            let note   = parsed["note"] as? String
            var items: [ResultItem] = []
            if let rawItems = parsed["items"] as? [[String: Any]] {
                for item in rawItems.prefix(3) {
                    items.append(ResultItem(
                        label:  item["label"]  as? String ?? "",
                        detail: item["detail"] as? String ?? "",
                        url:    item["url"]    as? String
                    ))
                }
            }
            state.searchResult = SearchResult(title: title, items: items, note: note)
        } else {
            // Fallback: show raw text in 3-line chunks
            let lines = cleanText.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(3)
            state.searchResult = SearchResult(
                title: "Response",
                items: lines.map { ResultItem(label: $0, detail: "", url: nil) },
                note: nil
            )
        }

        state.stateOverride = nil
        state.view = .result
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
    }

    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }

    // MARK: - File content block builder (Anthropic shape)

    private func readFileAsBlock(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let base64 = data.base64EncodedString()

        if ext == "pdf" {
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": base64]]
        } else if ["jpg", "jpeg"].contains(ext) {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
        } else if ext == "png" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": base64]]
        } else if ext == "gif" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/gif", "data": base64]]
        } else if ext == "webp" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/webp", "data": base64]]
        } else {
            // Text/code — inline as text if <= 200 KB
            guard data.count <= 200_000,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return ["type": "text", "text": "File contents:\n\(text)"]
        }
    }
}
