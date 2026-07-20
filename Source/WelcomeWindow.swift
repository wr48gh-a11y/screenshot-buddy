import SwiftUI
import AppKit

// MARK: - Welcome (Concept C — cinematic)

enum WelcomeWindow {
    private static var window: NSWindow?

    static func showIfNeeded(store: ScreenshotStore) {
        guard store.folderURL == nil else { return }
        show(store: store)
    }

    static func show(store: ScreenshotStore) {
        if window == nil {
            let view = WelcomeView(
                connect: {
                    store.chooseFolder()
                    if store.folderURL != nil { close() }
                },
                dismiss: { close() })
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.backgroundColor = NSColor(red: 0.07, green: 0.047, blue: 0.149, alpha: 1)
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct WelcomeView: View {
    let connect: () -> Void
    let dismiss: () -> Void

    private static var headline: AttributedString = {
        var s = AttributedString("Welcome to Screenshot Buddy")
        s.foregroundColor = .white
        if let range = s.range(of: "Screenshot Buddy") {
            s[range].foregroundColor = Color(red: 0.788, green: 0.596, blue: 1.0)
        }
        return s
    }()

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.29, green: 0.184, blue: 0.62),
                         Color(red: 0.141, green: 0.102, blue: 0.302),
                         Color(red: 0.071, green: 0.047, blue: 0.149)],
                center: .init(x: 0.5, y: 1.15), startRadius: 30, endRadius: 760)

            VStack(spacing: 0) {
                Spacer()
                BuddyMark()
                    .stroke(Theme.pill,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 62, height: 62)
                    .shadow(color: Theme.accent1.opacity(0.4), radius: 16)
                    .padding(.bottom, 26)

                Text(Self.headline)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)

                Text("Every screenshot lives in your menu bar.\nWhen it starts to pile up, sweep it all away.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.725, green: 0.682, blue: 0.902))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 18)
                    .padding(.horizontal, 40)

                Button(action: connect) {
                    Text("Connect Your Screenshots Folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 34)
                        .background(Capsule().fill(Theme.pill))
                        .shadow(color: Theme.accent1.opacity(0.5), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 34)

                Button(action: dismiss) {
                    Text("Maybe later")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.561, green: 0.518, blue: 0.769))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                Spacer()
            }
            .padding(48)
        }
        .frame(width: 880, height: 600)
        .environment(\.colorScheme, .dark)
    }
}
