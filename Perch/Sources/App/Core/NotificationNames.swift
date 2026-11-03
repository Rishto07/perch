import Foundation

// MARK: - Notification names
// Central registry for every Notification.Name used across Perch.
// Keep them all here so observers and posters can never drift apart.

extension Notification.Name {
    // Hook server → island
    static let hookExpand = Notification.Name("perch.hookExpand")
    static let hookReveal = Notification.Name("perch.hookReveal")

    // Island interactions
    static let islandCollapse = Notification.Name("perch.islandCollapse")
    static let islandAction = Notification.Name("perch.islandAction")

    // Bot / character
    static let triggerEmote = Notification.Name("perch.triggerEmote")
    static let triggerSlap = Notification.Name("perch.triggerSlap")
    static let botDizzy = Notification.Name("perch.botDizzy")
    static let botGreet = Notification.Name("perch.botGreet")
    static let botBlink = Notification.Name("perch.botBlink")
    static let botSetTgEs = Notification.Name("perch.botSetTgEs")
    static let botGulp = Notification.Name("perch.botGulp")
    static let botMorphTo = Notification.Name("perch.botMorphTo")

    // Settings
    static let openFullSettings = Notification.Name("perch.openFullSettings")

    // Greeting ↔ IslandWindowController
    static let greetComplete = Notification.Name("perch.greetComplete")
    static let greetingHover = Notification.Name("perch.greetingHover")
    static let greetingInterrupt = Notification.Name("perch.greetingInterrupt")
}
