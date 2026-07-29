import SwiftUI
import ServiceManagement

// MARK: - Launch at login

/// Wraps `SMAppService.mainApp` (macOS 13+), which registers the app itself as a login item.
/// No helper bundle and no extra entitlement — it works as-is inside the App Sandbox.
///
/// `@MainActor`: every `@Published` mutation happens from SwiftUI menu/button closures, which
/// already run on main. Same compiler-checked contract as `ScreenshotStore`.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    /// Mirrors `SMAppService.mainApp.status`, and is deliberately *not* persisted. The user can
    /// switch the app off in System Settings › General › Login Items at any time, so a cached
    /// copy would go stale and render a checkmark that lies. `refresh()` re-reads the system.
    @Published private(set) var isEnabled = false

    /// macOS holds the registration but is waiting on the user to approve it in System Settings.
    /// Surfaced so the menu can point them there instead of silently doing nothing.
    @Published private(set) var requiresApproval = false

    /// Set when register/unregister throws, so the menu can admit the toggle didn't take.
    @Published private(set) var lastError: String?

    /// Whether the one-time post-sweep offer has already been answered.
    private static let offerMadeKey = "didOfferLaunchAtLogin"

    private init() { refresh() }

    // MARK: System state

    /// Re-read the login-item status from the system. Call whenever the panel is about to be
    /// shown — the user may have changed this in System Settings since we last looked.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    /// Register or unregister the app as a login item, then re-read the resulting status rather
    /// than assuming the call took effect.
    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: One-time offer

    /// True when we should proactively offer this after a sweep: the setting is off, and the
    /// user hasn't already answered the offer once.
    var shouldOffer: Bool {
        !isEnabled && !UserDefaults.standard.bool(forKey: Self.offerMadeKey)
    }

    func acceptOffer() {
        markOffered()
        set(true)
    }

    func declineOffer() {
        markOffered()
    }

    private func markOffered() {
        UserDefaults.standard.set(true, forKey: Self.offerMadeKey)
    }
}
