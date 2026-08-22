import SwiftUI
import AppKit

// MARK: - Main panel

struct PanelView: View {
    @EnvironmentObject var store: ScreenshotStore
    /// Singleton that outlives the view, so `@ObservedObject` rather than `@StateObject`.
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    /// `offerLogin` rides along in the result (rather than living in its own `@State`) so the
    /// auto-dismiss `.task(id:)` re-runs when it changes and can skip dismissing while the
    /// offer is on screen.
    struct SweepResult: Equatable { let count: Int; let permanent: Bool; let failed: Int; let offerLogin: Bool }
    @State private var sweepResult: SweepResult?

    var body: some View {
        VStack(spacing: 0) {
            if store.folderURL == nil {
                setupPanel
            } else if store.accessLost {
                lostAccessView
            } else {
                header
                Divider()
                gridView
                Divider()
                footer
            }
        }
        .frame(width: 424)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        // The user can flip this in System Settings while we're closed, so re-read on open.
        .onAppear { launchAtLogin.refresh() }
    }

    // No folder connected: a real, escapable panel (Connect + gear with Quit).
    private var setupPanel: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                settingsMenu
            }
            BuddyMark()
                .stroke(Theme.pill, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 46, height: 46)
            Text("Welcome to Screenshot Buddy")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Connect a folder to get started.")
                .font(.callout)
                .foregroundStyle(Theme.textDim)
            Button("Connect Your Screenshots Folder") { store.chooseFolder() }
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }

    // Chosen folder can't be read: offer a way back instead of a false "All Clear".
    private var lostAccessView: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                settingsMenu
            }
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.yellow)
            Text("Can't Reach This Folder")
                .font(.headline)
                .foregroundStyle(.white)
            Text("It may have been moved, renamed, or is on a drive that's disconnected.")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Reconnect Folder") { store.chooseFolder() }
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 60)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: store.files.isEmpty ? 0 : min(1, CGFloat(store.files.count) / 30))
                    .stroke(Theme.pill, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(store.files.count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.folderURL?.lastPathComponent ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(store.files.isEmpty
                     ? "All clear"
                     : "\(store.files.count) file\(store.files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button {
                if let url = store.folderURL { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open folder in Finder")
            settingsMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var gridView: some View {
        Group {
            if let result = sweepResult {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.green)
                    Text(result.permanent
                         ? "\(result.count) File\(result.count == 1 ? "" : "s") Deleted"
                         : "\(result.count) File\(result.count == 1 ? "" : "s") Swept to Trash")
                        .font(.headline)
                        .foregroundStyle(.white)
                    if result.failed > 0 {
                        Text("\(result.failed) couldn't be moved — they may be in use.")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    if result.permanent {
                        Button {
                            store.undoSweep()
                            withAnimation { sweepResult = nil }
                        } label: {
                            Text("Undo")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 22)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    if result.offerLogin { launchAtLoginOffer }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, result.offerLogin ? 24 : 36)
                .transition(.opacity)
                .task(id: result) {
                    // Don't time out a question. While the offer is up the confirmation stays
                    // put; answering it is what dismisses.
                    guard !result.offerLogin else { return }
                    // Purge is handled by a store-owned timer, so it happens even if the panel
                    // closes. This task only controls how long the confirmation stays visible.
                    try? await Task.sleep(nanoseconds: result.permanent ? 5_000_000_000 : 4_000_000_000)
                    withAnimation { sweepResult = nil }
                }
            } else if store.files.isEmpty {
                VStack(spacing: 8) {
                    BuddyMark()
                        .stroke(Theme.nearWhite,
                                style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 52, height: 52)
                        .padding(.bottom, 4)
                    Text("All Clear")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("No files in this folder.")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(store.files, id: \.self) { url in
                                ScreenshotCell(url: url)
                                    // Pin structural identity to the URL so a prepended screenshot
                                    // gets a fresh cell rather than a recycled slot. Note this alone
                                    // did not cure the wrong-cell drag; that fix is FileDragSource.
                                    .id(url)
                            }
                        }
                        .padding(12)
                        .id("grid-top")
                    }
                    // Always open at the top (newest shots), never at last session's scroll position.
                    .onAppear { proxy.scrollTo("grid-top", anchor: .top) }
                }
                // A ScrollView has no intrinsic height, and a MenuBarExtra window sizes itself
                // to its content's ideal size — so maxHeight alone lets the grid collapse to
                // zero. Give it a concrete, content-aware height instead (capped at 380).
                .frame(height: gridHeight)
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    if let sel = store.selection ?? store.files.first {
                        store.toggleQuickLook(sel)
                    }
                    return .handled
                }
                .onKeyPress(.rightArrow) { store.moveSelection(by: 1); return .handled }
                .onKeyPress(.leftArrow) { store.moveSelection(by: -1); return .handled }
            }
        }
    }

    /// Height for the screenshot grid: exactly fits the rows present, capped so a huge
    /// folder scrolls instead of growing the panel past the screen.
    private var gridHeight: CGFloat {
        // Cell = thumbnail (108) + spacing (5) + caption (~17) + cell padding (12).
        let rowHeight: CGFloat = 142
        let rows = CGFloat((store.files.count + 1) / 2)
        let spacing: CGFloat = 8 * max(0, rows - 1)
        let gridPadding: CGFloat = 24   // 12 top + 12 bottom
        return min(380, rows * rowHeight + spacing + gridPadding)
    }

    /// One-time nudge, shown on the sweep confirmation — the moment the app has just proved its
    /// worth. Deliberately not offered after "Delete Forever", where it would compete with the
    /// time-boxed Undo.
    private var launchAtLoginOffer: some View {
        VStack(spacing: 4) {
            Divider()
                .padding(.horizontal, 60)
                .padding(.bottom, 12)
            Text("Keep Screenshot Buddy handy?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("It'll be in your menu bar whenever you log in.")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
            HStack(spacing: 8) {
                Button {
                    launchAtLogin.declineOffer()
                    withAnimation { sweepResult = nil }
                } label: {
                    Text("Not Now")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textDim)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                Button {
                    launchAtLogin.acceptOffer()
                    withAnimation { sweepResult = nil }
                } label: {
                    Text("Open at Login")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(Theme.pill))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                let outcome = store.sweepAllToTrash()
                withAnimation {
                    sweepResult = .init(count: outcome.moved, permanent: false, failed: outcome.failed,
                                        offerLogin: outcome.moved > 0 && launchAtLogin.shouldOffer)
                }
            } label: {
                HStack(spacing: 8) {
                    BuddyMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 17, height: 17)
                    Text(store.files.isEmpty ? "Nothing to Sweep" : "Sweep to Trash")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if !store.files.isEmpty {
                        Text(store.reclaimable)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.pill))
                .shadow(color: Theme.accent1.opacity(0.42), radius: 9, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            Button {
                let outcome = store.deleteAll()
                withAnimation {
                    sweepResult = .init(count: outcome.moved, permanent: true, failed: outcome.failed,
                                        offerLogin: false)
                }
            } label: {
                Text("Delete Forever")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DestructiveOutlineButtonStyle())
            .frame(width: 132)
            .help("Permanently delete all screenshots. Skips the Trash; Undo available for 5 seconds.")
        }
        .disabled(store.files.isEmpty)
        .opacity(store.files.isEmpty ? 0.4 : 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Open at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.set($0) }))
            if launchAtLogin.requiresApproval {
                Button("Approve in Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
            }
            if let error = launchAtLogin.lastError {
                Text("Couldn't change login item: \(error)")
            }
            Divider()
            Button("Change Folder…") { store.chooseFolder() }
            Divider()
            Button("About Screenshot Buddy") { AboutWindow.show() }
            Divider()
            Button("Quit Screenshot Buddy") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Destructive button style

/// Outlined red capsule used for secondary destructive actions (e.g. "Delete Forever").
/// Kept separate from PillButtonStyle so the two hero/secondary treatments can't drift.
struct DestructiveOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(Theme.errorText)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Theme.destructive.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Theme.destructive.opacity(0.55), lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
