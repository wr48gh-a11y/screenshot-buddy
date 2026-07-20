import SwiftUI
import AppKit

// MARK: - About

enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let view = NSHostingView(rootView: AboutView())
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = view
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 72, height: 72)
                } else {
                    BuddyMark()
                        .stroke(Theme.pill, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 60, height: 60)
                }
            }
            .padding(.top, 10)
            Text("Screenshot Buddy")
                .font(.title2.weight(.semibold))
            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Your screenshots pile up.\nBuddy keeps the folder spotless.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()
            Text("© 2026 Hugh Southall. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
        }
        .padding(20)
        .frame(width: 280, height: 300)
    }
}
