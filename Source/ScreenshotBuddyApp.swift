import SwiftUI
import AppKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
#if DEBUG
    func applicationWillFinishLaunching(_ notification: Notification) {
        standDownIfAlreadyRunning()
    }

    /// A second copy of the app — an Xcode Debug build launched next to the installed one, or
    /// two login items pointing at different bundle paths — puts a second icon in the menu bar
    /// and gives two processes the same screenshot folder to sweep. `SMAppService.register()`
    /// records whichever bundle path happened to be running when the toggle flipped, so a copy
    /// run from DerivedData can outlive the debug session as its own login item.
    ///
    /// Whoever arrives second stands down, leaving the instance the user is already looking at.
    ///
    /// DEBUG only. That duplicate is a development artifact: for an installed copy,
    /// LaunchServices already activates the running instance rather than spawning a second
    /// process. Shipping this guard cost us an App Review rejection (2.1(a), "failed to launch
    /// any main window or menu bar extra") — a silent `exit(0)` is indistinguishable from an
    /// app that crashes on launch, and a menu bar app has no Dock icon to prove otherwise.
    private func standDownIfAlreadyRunning() {
        // Under XCTest the app IS the test host, and the installed copy is almost always running
        // too. Standing down there kills the test runner before it can connect ("Early
        // unexpected exit ... exited with code 0"), which reads as a broken test suite rather
        // than a duplicate app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let id = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return }
        // Surface the survivor before standing down, so a second launch never looks like a
        // no-op. `exit` rather than `NSApp.terminate`: terminate runs applicationWillTerminate,
        // and this instance has no state worth unwinding — restoreOnQuit belongs to the survivor.
        others.first?.activate()
        exit(0)
    }
#endif

    /// Launch shows the welcome window only when there's no folder yet. Deliberately *not*
    /// `reveal`: this also runs at login, and a "we're in your menu bar" window every single
    /// morning would be pestering. Explicit re-opens are the case that needs the reassurance.
    func applicationDidFinishLaunching(_ notification: Notification) {
        WelcomeWindow.showIfNeeded(store: .shared)
    }

    /// Re-opening the app (Finder, Launchpad, Spotlight, or a second launch of an installed
    /// copy) must put something on screen. This app is `LSUIElement`, so it has no Dock icon
    /// and no window of its own — without this handler, macOS just activates a process that
    /// shows nothing, which reads as "the app doesn't launch". App Review hit exactly that.
    ///
    /// Returning `true` tells AppKit we've handled the reopen ourselves.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { WelcomeWindow.reveal(store: .shared) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotStore.shared.restoreOnQuit()   // honor the undo window, don't purge on quit
    }
}

@main
struct ScreenshotBuddyApp: App {
    @StateObject private var store = ScreenshotStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
        } label: {
            Image(nsImage: BuddyMark.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
