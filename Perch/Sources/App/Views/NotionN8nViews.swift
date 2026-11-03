import SwiftUI

struct NotionCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#E8E8E8")).frame(width: 7, height: 7)
                Text("Notion").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Recent").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.notionPages.prefix(3)) { page in
                    Button {
                        if let url = URL(string: page.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 6) {
                            if let emoji = page.emoji {
                                Text(emoji).font(.system(size: 10)).frame(width: 14)
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#6B7079")).frame(width: 14)
                            }
                            Text(page.title).font(.system(size: 11))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(page.timeAgo).font(.system(size: 9))
                                .foregroundColor(Color(hex: "#4B5563"))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 102).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

// MARK: - n8n Execution Detail View

struct N8nDetailView: View {
    let task: AgentTask
    let onClose: () -> Void

    private var success: Bool  { task.state == .finished }
    private var accent: Color  { success ? Color(hex: "#22C55E") : Color(hex: "#F4505E") }
    private var statusLabel: String { success ? "Success" : "Failed" }
    private var detail: String? { task.steps.dropFirst().first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header: back button + workflow name + status badge
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)   // large hit area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)

                Text(task.steps.first ?? "Workflow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Detail body — monospaced, selectable
            if let detail {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 88)
            } else {
                Text(success ? "Completed successfully." : "No error details available.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())   // prevent taps falling through transparent areas
    }
}

// MARK: - Ticker (overview scrolling task steps) V2

