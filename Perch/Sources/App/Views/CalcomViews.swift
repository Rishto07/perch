import SwiftUI

struct CalcomCardView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedDate: Date? = nil
    @State private var selectedBooking: CalcomBooking? = nil
    @State private var displayMonth: Date = Date()
    @State private var displayHalf: Int = 1  // 1 = first half, 2 = second half

    var body: some View {
        Group {
            if let booking = selectedBooking {
                CalcomBookingDetailView(booking: booking) {
                    withAnimation(.easeOut(duration: 0.2)) { selectedBooking = nil }
                }
            } else if let date = selectedDate {
                CalcomDayView(
                    date: date,
                    bookings: bookingsFor(date),
                    onSelect: { b in withAnimation(.easeOut(duration: 0.2)) { selectedBooking = b } },
                    onBack:   { withAnimation(.easeOut(duration: 0.2)) { selectedDate = nil } }
                )
            } else {
                CalcomCalendarView(
                    displayMonth: $displayMonth,
                    displayHalf: $displayHalf,
                    bookings: appState.calcomBookings,
                    onSelect: { d in withAnimation(.easeOut(duration: 0.2)) { selectedDate = d } }
                )
            }
        }
        .onChange(of: appState.focusId) { _, _ in
            selectedDate = nil; selectedBooking = nil; displayHalf = 1
        }
    }

    private func bookingsFor(_ date: Date) -> [CalcomBooking] {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return appState.calcomBookings.filter { $0.dayKey == key }
                                      .sorted { $0.startTime < $1.startTime }
    }
}

struct CalcomCalendarView: View {
    @Binding var displayMonth: Date
    @Binding var displayHalf: Int
    let bookings: [CalcomBooking]
    let onSelect: (Date) -> Void

    private let cal = Calendar.current

    private var navLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return "\(f.string(from: displayMonth)) Q\(displayHalf)"
    }

    // 7 consecutive days per row, day 1 always at far left — no weekday alignment
    private var allWeeks: [[Date?]] {
        let comps = cal.dateComponents([.year, .month], from: displayMonth)
        let monthStart = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: displayMonth)!.count
        var result: [[Date?]] = []
        var chunk: [Date?] = []
        for i in 0..<daysInMonth {
            chunk.append(cal.date(byAdding: .day, value: i, to: monthStart)!)
            if chunk.count == 7 { result.append(chunk); chunk = [] }
        }
        if !chunk.isEmpty {
            while chunk.count < 7 { chunk.append(nil) }
            result.append(chunk)
        }
        return result
    }

    // Visible weeks for current half
    private var visibleWeeks: [[Date?]] {
        let all = allWeeks
        let splitAt = 2  // always 2 weeks per Q
        return displayHalf == 1 ? Array(all[0..<splitAt]) : Array(all[splitAt...])
    }

    private func hasBookings(_ d: Date) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return bookings.contains { $0.dayKey == key }
    }

    private func goBack() {
        if displayHalf == 1 {
            displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            displayHalf = 2
        } else {
            displayHalf = 1
        }
    }

    private func goForward() {
        if displayHalf == 1 {
            displayHalf = 2
        } else {
            displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            displayHalf = 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#C9956A")).frame(width: 7, height: 7)
                Text("Cal.com").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Schedule").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            HStack(spacing: 0) {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
                Text(navLabel).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD")).frame(maxWidth: .infinity)
                Button { goForward() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)

            VStack(spacing: 1) {
                ForEach(visibleWeeks.indices, id: \.self) { i in
                    CalcomWeekRow(week: visibleWeeks[i], hasBookings: hasBookings,
                                  isToday: cal.isDateInToday, onSelect: onSelect)
                }
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomWeekRow: View {
    let week: [Date?]
    let hasBookings: (Date) -> Bool
    let isToday: (Date) -> Bool
    let onSelect: (Date) -> Void

    private var weekLabel: String {
        guard let first = week.compactMap({ $0 }).first else { return "" }
        let f = DateFormatter(); f.dateFormat = "dd/MM"
        return f.string(from: first)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(weekLabel).font(.system(size: 7)).foregroundColor(Color(hex: "#4B5563"))
                .frame(width: 26, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                if let day = week[i] {
                    CalcomDayCell(day: day, hasEvents: hasBookings(day), isToday: isToday(day))
                        .contentShape(Rectangle()).onTapGesture { onSelect(day) }.frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity).frame(height: 18)
                }
            }
        }
    }
}

private struct CalcomDayCell: View {
    let day: Date
    let hasEvents: Bool
    let isToday: Bool
    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : Color(hex: "#9398A1"))
                .frame(width: 13, height: 13)
                .background(isToday ? Color(hex: "#C9956A").opacity(0.55) : Color.clear)
                .clipShape(Circle())
            Circle().fill(hasEvents ? Color(hex: "#C9956A") : Color.clear).frame(width: 3, height: 3)
        }
        .frame(height: 18)
    }
}

struct CalcomDayView: View {
    let date: Date
    let bookings: [CalcomBooking]
    let onSelect: (CalcomBooking) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(dayLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#C5C8CD"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            if bookings.isEmpty {
                Text("No calls scheduled").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    .padding(.leading, 116).padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(bookings) { b in
                        Button { onSelect(b) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#C9956A")).frame(width: 4, height: 4)
                                Text(b.timeLabel)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(hex: "#C9956A")).fixedSize()
                                Text(b.title).font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.system(size: 8))
                                    .foregroundColor(Color(hex: "#4B5563"))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#C9956A").opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108).padding(.trailing, 12).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
    private var dayLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f.string(from: date)
    }
}

struct CalcomBookingDetailView: View {
    let booking: CalcomBooking
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(booking.timeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#C9956A"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(booking.title).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                if let name = booking.attendeeName, !name.isEmpty {
                    CalcomDetailRow(icon: "person.fill", text: name, size: 11)
                }
                if let email = booking.attendeeEmail, !email.isEmpty {
                    CalcomDetailRow(icon: "envelope.fill", text: email, size: 10, truncate: true)
                }
                if let notes = booking.attendeeNotes, !notes.isEmpty {
                    CalcomDetailRow(icon: "note.text", text: notes, size: 10, lines: 2)
                }
            }
            .padding(.leading, 114).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomDetailRow: View {
    let icon: String
    let text: String
    var size: CGFloat = 11
    var truncate: Bool = false
    var lines: Int = 1
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079")).frame(width: 10)
            Text(text).font(.system(size: size)).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(lines).truncationMode(truncate ? .middle : .tail)
        }
    }
}

// MARK: - Notion Card View

