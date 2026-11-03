import SwiftUI

struct IntegrationCardView: View {
    let task: AgentTask
    @Binding var showingDetail: Bool
    @ObservedObject private var appState = AppState.shared

    private var isConfigured: Bool {
        switch task.id {
        case "integration_claude":
            #if APPSTORE
            // Sandboxed: can't read ~/.claude directly — check install flag set by HookServer.
            return UserDefaults.standard.bool(forKey: "perchHooksInstalled")
            #else
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any],
                  let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
            return ss.contains { ($0["hooks"] as? [[String: Any]])?.contains {
                HookServer.isOwnHookCommand(($0["command"] as? String) ?? "")
            } ?? false }
            #endif
        case "integration_codex",
             "integration_opencode",
             "integration_zcode",
             "integration_generic":
            // Agent pills need no key and no hook check: sessions appear on their
            // own once the adapter (see agents/) forwards events. Always "ready".
            return true
        case "integration_resend":  return KeychainStore.shared.get("resend-api-key") != nil
        case "integration_n8n":     return KeychainStore.shared.get("n8n-api-key")    != nil
        case "integration_vercel":  return KeychainStore.shared.get("vercel-token")   != nil
        case "integration_github":  return KeychainStore.shared.get("github-token")   != nil
        case "integration_stripe":  return KeychainStore.shared.get("stripe-api-key") != nil
        case "integration_notion":  return KeychainStore.shared.get("notion-api-key") != nil
        case "integration_calcom":  return KeychainStore.shared.get("calcom-api-key") != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_claude",
             "integration_codex",
             "integration_opencode",
             "integration_zcode",
             "integration_generic":
            return nil  // agent pills use the project button below
        case "integration_resend":  return URL(string: "https://resend.com/emails")
        case "integration_n8n":
            if let s = KeychainStore.shared.get("n8n-url") { return URL(string: s) }
            return nil
        case "integration_vercel":  return URL(string: "https://vercel.com/dashboard")
        case "integration_github":  return URL(string: "https://github.com")
        case "integration_stripe":  return URL(string: "https://dashboard.stripe.com/payments")
        case "integration_notion":  return URL(string: "https://notion.so")
        case "integration_calcom":  return URL(string: "https://app.cal.com/bookings")
        default: return nil
        }
    }

    // Agent pill with an active session: show ticker layout (same as overview).
    // Covers Claude, Codex, OpenCode, Zcode and the generic fallback.
    private var agentSessionActive: Bool {
        Self.agentTaskIds.contains(task.id) && (task.state != .idle || !task.steps.isEmpty)
    }

    private static let agentTaskIds: Set<String> = [
        "integration_claude", "integration_codex", "integration_opencode",
        "integration_zcode", "integration_generic",
    ]

    /// Human label for the agent behind a task ("Claude Code", "Codex", …).
    private var agentLabel: String {
        switch task.id {
        case "integration_codex":    return "Codex"
        case "integration_opencode": return "OpenCode"
        case "integration_zcode":    return "Zcode"
        case "integration_generic":  return "Agent"
        default:                     return "Claude Code"
        }
    }

    // n8n with a finished execution: show result row instead of "Open n8n" button
    private var n8nHasActivity: Bool {
        task.id == "integration_n8n" && !task.steps.isEmpty &&
        (task.state == .finished || task.state == .error)
    }

    // Vercel with recent deployments
    private var vercelHasActivity: Bool {
        task.id == "integration_vercel" && !appState.vercelDeployments.isEmpty
    }

    // Resend with recent emails
    private var resendHasData: Bool {
        task.id == "integration_resend" && !appState.resendEmails.isEmpty
    }

    // GitHub with stats loaded
    private var githubHasData: Bool {
        task.id == "integration_github" && appState.githubStats != nil
    }

    // Stripe: show card as soon as first poll completes (balance OR payments)
    private var stripeHasData: Bool {
        task.id == "integration_stripe" && appState.stripeLoaded
    }

    // Cal.com: show calendar as soon as first poll completes
    private var calcomHasData: Bool {
        task.id == "integration_calcom" && appState.calcomLoaded
    }

    // Notion: show pages as soon as first poll completes
    private var notionHasData: Bool {
        task.id == "integration_notion" && appState.notionLoaded
    }

    var body: some View {
        if showingDetail && n8nHasActivity {
            N8nDetailView(task: task) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if showingDetail && vercelHasActivity {
            VercelDetailView(deployment: appState.vercelDeployments[0]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if vercelHasActivity {
            VercelDeploymentListView(deployments: appState.vercelDeployments, onOpenDetail: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if resendHasData {
            ResendCardView(emails: appState.resendEmails, total: appState.resendTotal)
                .transition(.opacity)
        } else if githubHasData {
            GitHubStatsCardView(stats: appState.githubStats!)
                .transition(.opacity)
        } else if stripeHasData {
            StripeCardView()
                .transition(.opacity)
        } else if calcomHasData {
            CalcomCardView()
                .transition(.opacity)
        } else if notionHasData {
            NotionCardView()
                .transition(.opacity)
        } else if agentSessionActive {
            // Active session view — reuse overview layout
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                    Text(agentLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 2)
                    if task.steps.count > 1 {
                        Text("\(min(task.stepIndex + 1, task.steps.count))/\(task.steps.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                TickerView(task: task)
                    .frame(height: 44)
                    .padding(.top, 6)
                    .padding(.leading, 108)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        } else {
            // Idle / not connected view — slides in from left when returning from detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.id == "integration_claude" ? "VS Code" : task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text("Integration")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    let stripeErr = task.id == "integration_stripe" ? appState.stripeError
                                  : task.id == "integration_calcom"  ? appState.calcomError
                                  : nil
                    let dot = stripeErr != nil ? Color(hex: "#F4505E")
                            : isConfigured    ? Color(hex: "#22C55E")
                            :                   Color(hex: "#F4505E")
                    let label = stripeErr
                        ?? (Self.agentTaskIds.contains(task.id) ? "Waiting for session…"
                            : isConfigured ? "Connected · loading…" : "Key not configured")
                    Circle().fill(dot).frame(width: 5, height: 5)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if task.id == "integration_claude" {
                        Button("Open Visual Studio Code") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if Self.agentTaskIds.contains(task.id) {
                        Button("Open project") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if n8nHasActivity {
                        // Clickable pill — tap to open execution detail
                        let success = task.state == .finished
                        let accent  = success ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                        }) {
                            HStack(spacing: 5) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Text(task.steps.first ?? "Workflow")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7079"))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else if let url = openURL {
                        Button("Open \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_stripe" {
                        if isConfigured {
                            Button("Refresh") { Task { @MainActor in StripePoller.shared.pollNow() } }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#0570DE").opacity(0.85))
                                .buttonStyle(.plain)
                        }
                    }
                    if task.id == "integration_calcom" && isConfigured {
                        Button("Refresh") { Task { @MainActor in CalcomPoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C9956A").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if !isConfigured {
                        Button("Settings…") {
                            NotificationCenter.default.post(name: .openFullSettings, object: nil)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func openVSCode() {
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

        // If we have a project folder, open it directly in VS Code
        if let cwd = task.sessionCwd, !cwd.isEmpty, let appURL = appURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return
        }

        // No cwd: activate running instance or launch fresh
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }
}

// MARK: - Vercel Deployment List View

