import SwiftUI

struct ResendPulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color(hex: "#22C55E"))
            .frame(width: 4, height: 4)
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct ResendCardView: View {
    let emails: [ResendEmail]
    let total: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#22C55E"))
                    .frame(width: 7, height: 7)
                Text("Resend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Emails")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                if let total {
                    ResendPulseDot()
                    Text("\(total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .monospacedDigit()
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Email rows — first is highlighted, rest plain (same structure as Vercel list)
            VStack(alignment: .leading, spacing: 3) {
                if let first = emails.first {
                    let accent = Color(hex: first.isDelivered ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(first.recipientShort)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(first.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                        if !first.subject.isEmpty {
                            Text(first.subject)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#4D5159"))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                ForEach(Array(emails.dropFirst().prefix(2))) { email in
                    let accent = Color(hex: email.isDelivered ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(email.recipientShort)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(email.timeAgo)
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

// MARK: - GitHub Stats Card View

