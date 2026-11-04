import SwiftUI

// MARK: - Agent rail
//
// Pip is the only character in the island. Every other agent is a small
// bird perched on one rail: colour says who, motion says what they are doing.
// The birds are drawn in the same side-profile language as the Pip mark —
// crown spike, oval eye, short beak, teardrop body, legs on the rail —
// so they read as Perch, not as a generic icon set. There is no per-agent
// bot engine and no face: one glyph, one transform, at 20 fps.

struct AgentRailView: View {
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    private var displayTasks: [AgentTask] {
        Array(others.prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if displayTasks.isEmpty {
                HStack(spacing: 6) {
                    PerchedBirdMark(color: Color(hex: "#6B7079"), size: 13, state: .idle)
                        .opacity(0.45)
                    Text("No other agents")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#4B5563"))
                }
                .frame(height: 44)
            } else {
                ZStack {
                    RailLine()
                        .offset(y: 4)
                    HStack(spacing: 0) {
                        ForEach(displayTasks) { task in
                            AgentTokenView(task: task) {
                                state.setFocus(task.id)
                                SoundEngine.shared.play("blip")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 48)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One agent on the rail: a perched bird above the line, its name below.
private struct AgentTokenView: View {
    let task: AgentTask
    let onTap: () -> Void
    @State private var hovered = false

    // Agent tokens keep their agent label (same as the VS Code token); the
    // project name lives in the session card.
    private var displayName: String {
        switch task.id {
        case "integration_claude":   return "VS Code"
        case "integration_codex":    return "Codex"
        case "integration_opencode": return "OpenCode"
        case "integration_zcode":    return "Zcode"
        case "integration_generic":  return "Agent"
        default:                     return task.name
        }
    }

    /// Badged and busy agents perch on top of the rail; idle ones rest on it.
    private var perched: Bool {
        task.pillBadge != nil || task.state != .idle
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    PerchedBirdMark(color: Color(hex: task.color), size: 24, state: task.state)
                        .frame(width: 26, height: 24)
                    if let badge = task.pillBadge {
                        AgentBadgeView(badge: badge, taskColor: task.color)
                            .offset(x: 1, y: -2)
                    }
                }
                Text(displayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(hovered
                                     ? Color(hex: task.color).lighter(by: 0.25)
                                     : Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 1)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .offset(y: hovered ? -3 : (perched ? -1.5 : 0))
            .shadow(color: Color(hex: task.color).opacity(hovered ? 0.35 : 0), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                hovered = inside
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: perched)
        .help(displayName)
    }
}

// MARK: - The rail itself

private struct RailLine: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.11), location: 0.16),
                .init(color: .white.opacity(0.11), location: 0.84),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Perched bird glyph

/// The agent glyph: a small bird perched on the rail, in the Pip mark's
/// language — crown spike, oval eye, short beak, teardrop body, legs
/// gripping the line. Pip remains the only bird with a face and a body
/// of his own; these are silhouettes that say "agent on a perch".
///
/// Motion is the state language —
///   idle      slow breathing
///   working   leans forward, wing-vane light sweeps
///   approval  a hop, amber glow
///   finished  one tail-flick, green glint
///   error     a brief ruffle, red glow
struct PerchedBirdMark: View {
    let color: Color
    let size: CGFloat
    let state: BotState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, canvas in
                draw(&context, canvas: canvas, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, canvas: CGSize, time: TimeInterval) {
        let motion = motion(at: time)
        let unit = min(canvas.width, canvas.height) / 24
        let mid = CGPoint(x: canvas.width / 2, y: canvas.height / 2)

        if motion.glow > 0.01 {
            let halo = CGRect(x: mid.x - 13, y: mid.y - 13, width: 26, height: 26)
            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [
                        motion.glowColor.opacity(0.40 * motion.glow),
                        motion.glowColor.opacity(0),
                    ]),
                    center: mid,
                    startRadius: 0,
                    endRadius: canvas.width * 0.62
                )
            )
        }

        context.translateBy(x: mid.x, y: mid.y + motion.lift * unit)
        context.rotate(by: .degrees(motion.rotation))
        context.scaleBy(x: unit * motion.scale, y: unit * motion.scale)
        context.translateBy(x: -12, y: -12)

        let body = Self.body
        // Legs go down first so the body sits over their tops.
        if canvas.width >= 16 {
            context.stroke(Self.legs, with: .color(.black.opacity(0.55)), lineWidth: 1.1)
        }

        context.drawLayer { layer in
            layer.fill(
                body,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.95), color.opacity(0.60)]),
                    startPoint: CGPoint(x: 20, y: 2),
                    endPoint: CGPoint(x: 6, y: 19)
                )
            )

            // A light that travels across the wing while working.
            if let sweep = motion.sweep {
                let x = -10 + 44 * sweep
                var shine = layer
                shine.clip(to: body)
                shine.fill(
                    Path(CGRect(x: x - 3, y: -2, width: 6, height: 28)),
                    with: .linearGradient(
                        Gradient(colors: [
                            .white.opacity(0),
                            .white.opacity(0.10 + 0.32 * motion.glow),
                            .white.opacity(0),
                        ]),
                        startPoint: CGPoint(x: x - 3, y: 0),
                        endPoint: CGPoint(x: x + 3, y: 0)
                    )
                )
            }

            // Wing and eye are detail: below 16 px they are noise.
            if canvas.width >= 16 {
                layer.fill(Self.wing, with: .color(.black.opacity(0.18)))
                layer.fill(Self.eye, with: .color(Color(hex: "#10131A")))
            } else {
                layer.fill(Self.eyeSmall, with: .color(Color(hex: "#10131A")))
            }
        }
    }

    private struct Motion {
        var scale: CGFloat = 1
        var rotation: Double = 0
        var lift: CGFloat = 0
        var glow: Double = 0
        var sweep: Double? = nil
        var glowColor: Color
    }

    private func motion(at time: TimeInterval) -> Motion {
        // A 12 s cycle keeps every state's phase stable across little pauses
        // (the island hides, the view comes back) without a stored clock.
        let t = time.truncatingRemainder(dividingBy: 12)
        switch state {
        case .working, .thinking, .searching:
            // Leans into the work, with the wing light sweeping.
            return Motion(
                scale: 1.03,
                rotation: 2.2 * sin(t * 2 * .pi / 2.4),
                lift: -0.2,
                glow: 0.5 + 0.35 * sin(t * 2 * .pi / 1.2),
                sweep: t.truncatingRemainder(dividingBy: 1.8) / 1.8,
                glowColor: color
            )
        case .approval, .question:
            let q = t.truncatingRemainder(dividingBy: 1.8)
            let hop = q < 0.35 ? sin(q / 0.35 * .pi) : 0
            return Motion(
                scale: 1,
                rotation: -4 * hop,
                lift: -2.5 * hop,
                glow: 0.55,
                glowColor: state == .question ? Color(hex: "#22D3EE") : Color(hex: "#F5A524")
            )
        case .error:
            let q = t.truncatingRemainder(dividingBy: 2.2)
            let shake = q < 0.6 ? sin(q / 0.6 * .pi * 3) * (1 - q / 0.6) : 0
            return Motion(
                scale: 1,
                rotation: 8 * shake,
                lift: 0,
                glow: 0.6 * (0.5 + 0.5 * (1 - q / 2.2)),
                glowColor: Color(hex: "#F4505E")
            )
        case .finished:
            let q = t.truncatingRemainder(dividingBy: 2.6)
            let flick = q < 0.3 ? sin(q / 0.3 * .pi) : 0
            return Motion(
                scale: 1,
                rotation: -12 * flick,
                lift: -1.0 * flick,
                glow: 0.35 * flick,
                glowColor: Color(hex: "#22C55E")
            )
        case .ratelimit, .sleeping, .dizzy:
            let breath = sin(t * 2 * .pi / 5)
            return Motion(
                scale: 1 + 0.018 * breath,
                rotation: 0.5 * breath,
                lift: 0.3 * breath,
                glowColor: color
            )
        default:
            let breath = sin(t * 2 * .pi / 3.8)
            return Motion(
                scale: 1 + 0.025 * breath,
                rotation: 0.9 * breath,
                lift: 0.35 * breath,
                glowColor: color
            )
        }
    }

    // MARK: Geometry (24 × 24 design box, bird facing right)

    /// Body silhouette: crown spike + head + short beak + teardrop body
    /// tapering to a tail at the left. One closed path, so it reads as a
    /// silhouette even at 11 px.
    private static let body: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 12.5, y: 5.2))
        path.addCurve(
            to: CGPoint(x: 16.6, y: 4.6),
            control1: CGPoint(x: 14.0, y: 4.2),
            control2: CGPoint(x: 15.5, y: 4.2)
        )
        path.addLine(to: CGPoint(x: 19.2, y: 0.7))   // crown spike tip
        path.addLine(to: CGPoint(x: 19.9, y: 5.0))   // spike base, forehead
        path.addCurve(
            to: CGPoint(x: 20.7, y: 7.6),
            control1: CGPoint(x: 20.5, y: 6.2),
            control2: CGPoint(x: 20.7, y: 6.8)
        )
        path.addCurve(
            to: CGPoint(x: 23.0, y: 9.7),            // beak tip
            control1: CGPoint(x: 21.5, y: 8.6),
            control2: CGPoint(x: 22.2, y: 9.2)
        )
        path.addCurve(
            to: CGPoint(x: 19.8, y: 11.0),           // back to throat
            control1: CGPoint(x: 21.8, y: 10.6),
            control2: CGPoint(x: 20.6, y: 10.9)
        )
        path.addCurve(
            to: CGPoint(x: 16.5, y: 15.0),
            control1: CGPoint(x: 18.5, y: 12.5),
            control2: CGPoint(x: 17.8, y: 13.8)
        )
        path.addCurve(
            to: CGPoint(x: 11.0, y: 18.6),           // belly
            control1: CGPoint(x: 14.5, y: 17.5),
            control2: CGPoint(x: 12.8, y: 18.5)
        )
        path.addCurve(
            to: CGPoint(x: 6.0, y: 18.2),
            control1: CGPoint(x: 8.5, y: 18.9),
            control2: CGPoint(x: 7.2, y: 18.6)
        )
        path.addCurve(
            to: CGPoint(x: 3.9, y: 14.6),            // tail tip
            control1: CGPoint(x: 4.8, y: 17.2),
            control2: CGPoint(x: 4.2, y: 16.0)
        )
        path.addCurve(
            to: CGPoint(x: 7.0, y: 12.0),
            control1: CGPoint(x: 5.5, y: 13.0),
            control2: CGPoint(x: 6.2, y: 12.5)
        )
        path.addCurve(
            to: CGPoint(x: 10.5, y: 8.0),
            control1: CGPoint(x: 8.5, y: 10.5),
            control2: CGPoint(x: 9.5, y: 9.0)
        )
        path.addCurve(
            to: CGPoint(x: 12.5, y: 5.2),
            control1: CGPoint(x: 11.0, y: 6.5),
            control2: CGPoint(x: 11.5, y: 5.8)
        )
        path.closeSubpath()
        return path
    }()

    /// Wing: a darker vane folded against the body.
    private static let wing: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 9.2, y: 10.2))
        path.addCurve(
            to: CGPoint(x: 15.2, y: 11.2),
            control1: CGPoint(x: 11.5, y: 9.4),
            control2: CGPoint(x: 14.0, y: 10.0)
        )
        path.addCurve(
            to: CGPoint(x: 14.6, y: 15.8),
            control1: CGPoint(x: 15.6, y: 13.0),
            control2: CGPoint(x: 15.4, y: 14.8)
        )
        path.addCurve(
            to: CGPoint(x: 9.0, y: 16.4),
            control1: CGPoint(x: 12.5, y: 17.0),
            control2: CGPoint(x: 10.5, y: 17.2)
        )
        path.addCurve(
            to: CGPoint(x: 9.2, y: 10.2),
            control1: CGPoint(x: 7.6, y: 14.5),
            control2: CGPoint(x: 7.8, y: 11.5)
        )
        path.closeSubpath()
        return path
    }()

    /// Eye: the Pip mark's oval eye, as a dark dot.
    private static let eye = Path(ellipseIn: CGRect(x: 15.95, y: 5.75, width: 2.5, height: 2.5))
    private static let eyeSmall = Path(ellipseIn: CGRect(x: 16.4, y: 6.2, width: 1.6, height: 1.6))

    /// Legs gripping the rail, with little feet.
    private static let legs: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 11.0, y: 18.3))
        path.addLine(to: CGPoint(x: 11.0, y: 21.2))
        path.move(to: CGPoint(x: 14.2, y: 18.5))
        path.addLine(to: CGPoint(x: 14.2, y: 21.2))
        path.move(to: CGPoint(x: 10.0, y: 21.2))
        path.addLine(to: CGPoint(x: 12.0, y: 21.2))
        path.move(to: CGPoint(x: 13.2, y: 21.2))
        path.addLine(to: CGPoint(x: 15.2, y: 21.2))
        return path
    }()
}

// MARK: - Badge (approval / finished / error)

struct AgentBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}
