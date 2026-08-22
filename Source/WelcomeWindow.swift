import SwiftUI
import AppKit

// MARK: - Welcome (Concept C — cinematic)

/// `@MainActor`: this is AppKit window management that reads/writes the `@MainActor` store
/// (checking `folderURL`, calling `chooseFolder`). Window code always runs on main.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?

    static func showIfNeeded(store: ScreenshotStore) {
        guard store.folderURL == nil else { return }
        show(store: store)
    }

    /// Put *something* on screen — used on launch and on every re-open.
    ///
    /// The old launch path only ever showed the welcome window, and only when no folder was
    /// connected. Once a folder was chosen the app became entirely invisible apart from its
    /// menu bar icon, which on a notched Mac with a busy menu bar can be pushed off-screen
    /// entirely. Re-launching then did nothing at all. That combination is what App Review
    /// reported as "failed to launch any main window or menu bar extra".
    static func reveal(store: ScreenshotStore) {
        if store.folderURL == nil {
            show(store: store)
        } else {
            showMenuBarHint()
        }
    }

    private static var hintWindow: NSWindow?

    /// Small "we're up here" pointer for the already-configured case, where the welcome
    /// window's "connect a folder" copy would be wrong.
    static func showMenuBarHint() {
        if hintWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.backgroundColor = NSColor(red: 0.07, green: 0.047, blue: 0.149, alpha: 1)
            w.contentView = NSHostingView(rootView: MenuBarHintView(dismiss: { closeHint() }))
            w.isReleasedWhenClosed = false
            w.center()
            hintWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        hintWindow?.makeKeyAndOrderFront(nil)
    }

    static func closeHint() {
        hintWindow?.close()
        hintWindow = nil
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

/// Shown when the app is re-opened but a folder is already connected: there's nothing to set
/// up, so the only useful thing to say is where the app actually lives.
struct MenuBarHintView: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.071, green: 0.047, blue: 0.149)
            VStack(spacing: 0) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.788, green: 0.596, blue: 1.0))
                    .padding(.bottom, 14)
                Text("Screenshot Buddy is running")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text("Look for the icon in your menu bar,\nat the top-right of your screen.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.725, green: 0.682, blue: 0.902))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 8)
                Button(action: dismiss) {
                    Text("Got It")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 26)
                        .background(Capsule().fill(Theme.pill))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(28)
        }
        .frame(width: 420, height: 220)
        .environment(\.colorScheme, .dark)
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
