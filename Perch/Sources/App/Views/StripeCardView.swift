import SwiftUI

struct StripeCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#0570DE"))
                    .frame(width: 7, height: 7)
                Text("Stripe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Payments")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Balance
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(balanceFormatted)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 1.2), value: appState.stripeDisplayBalance)
                Text(appState.stripeCurrency.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.bottom, 1)
            }
            .padding(.leading, 108)
            .padding(.top, 4)

            // Payment rows (animated list)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.stripePayments) { payment in
                    StripePaymentRow(payment: payment)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82),
                        value: appState.stripePayments.map(\.id))
            .padding(.leading, 108)
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var balanceFormatted: String {
        String(format: "%.2f", Double(appState.stripeDisplayBalance) / 100.0)
    }
}

private struct StripePaymentRow: View {
    let payment: StripePayment

    var body: some View {
        let accent = payment.isSuccess ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text(payment.description ?? "Payment")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text("+\(payment.amountFormatted)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#22C55E"))
                .fixedSize()
            Text(payment.timeAgo)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cal.com Card View

