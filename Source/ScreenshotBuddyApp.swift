import SwiftUI
import AppKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WelcomeWindow.showIfNeeded(store: .shared)
    }
    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotStore.shared.purgeSweep()   // finalize any pending sweep on quit
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
            Image(nsImage: BuddyMark.menuBarImage(height: 18))
        }
        .menuBarExtraStyle(.window)
    }
}
