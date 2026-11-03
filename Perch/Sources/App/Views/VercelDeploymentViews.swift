import SwiftUI

struct VercelDeploymentListView: View {
    let deployments: [VercelDeployment]
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#7C5CFF"))
                    .frame(width: 7, height: 7)
                Text("Vercel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Deployments")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Deployment rows
            VStack(alignment: .leading, spacing: 3) {
                // First deployment — highlighted, with detail button
                if let first = deployments.first {
                    let accent = Color(hex: first.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(first.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(first.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                        Button(action: onOpenDetail) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Remaining deployments — plain rows, identical structure → perfect alignment
                ForEach(Array(deployments.dropFirst().prefix(2))) { dep in
                    let accent = Color(hex: dep.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(dep.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(dep.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

// MARK: - Vercel Deployment Detail View

struct VercelDetailView: View {
    let deployment: VercelDeployment
    let onClose: () -> Void

    private var accent: Color { Color(hex: deployment.isSuccess ? "#22C55E" : "#F4505E") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)
                Text(deployment.projectName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(deployment.statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                if let commit = deployment.commitMessage {
                    Text(commit)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let branch = deployment.branch {
                        Label(branch, systemImage: "arrow.branch")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    Text(deployment.timeAgo + " ago")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                Button(action: {
                    if let url = URL(string: "https://\(deployment.url)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(deployment.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "#7C5CFF").opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: - Resend Card View

