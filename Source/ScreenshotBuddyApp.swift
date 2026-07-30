import SwiftUI
import AppKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        standDownIfAlreadyRunning()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WelcomeWindow.showIfNeeded(store: .shared)
    }

    /// A second copy of the app — an Xcode Debug build launched next to the installed one, or
    /// two login items pointing at different bundle paths — puts a second icon in the menu bar
    /// and gives two processes the same screenshot folder to sweep. `SMAppService.register()`
    /// records whichever bundle path happened to be running when the toggle flipped, so a copy
    /// run from DerivedData can outlive the debug session as its own login item.
    ///
    /// Whoever arrives second stands down, leaving the instance the user is already looking at.
    private func standDownIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return }
        // `exit` rather than `NSApp.terminate`: terminate runs applicationWillTerminate, and
        // this instance has no state worth unwinding — restoreOnQuit belongs to the survivor.
        exit(0)
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
