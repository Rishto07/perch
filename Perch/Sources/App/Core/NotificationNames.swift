import Foundation

// MARK: - Notification names
// Central registry for every Notification.Name used across Perch.
// Keep them all here so observers and posters can never drift apart.

extension Notification.Name {
    static let hookExpand = Notification.Name("perch.hookExpand")
}
