import SwiftUI
import AppKit

// MARK: - Theme

enum Theme {
    static let bgTop = Color(red: 0.106, green: 0.063, blue: 0.208)     // #1b1035
    static let bgMid = Color(red: 0.141, green: 0.102, blue: 0.302)     // #241a4d
    static let bgBottom = Color(red: 0.063, green: 0.063, blue: 0.141)  // #101024
    static let accent1 = Color(red: 0.482, green: 0.302, blue: 1.0)     // #7b4dff
    static let accent2 = Color(red: 0.706, green: 0.302, blue: 1.0)     // #b44dff
    static let textDim = Color(red: 0.725, green: 0.682, blue: 0.902)   // #b9aee6

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgMid, bgBottom], startPoint: .top, endPoint: .bottom)
    }
    static var pill: LinearGradient {
        LinearGradient(colors: [accent1, accent2], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Buddy mark (the spiral glyph)

/// Shared geometry for the spiral logo mark (from icon-kit/mark.svg).
/// One source of truth for the points + bounding box, used by both the SwiftUI `BuddyMark`
/// shape and the AppKit `menuBarImage` generator so they can't drift apart.
enum BuddyGlyph {
    /// Points in the 1024×1024 source viewBox.
    static let pts: [CGPoint] = [
        .init(x: 498, y: 468), .init(x: 618, y: 468), .init(x: 618, y: 601),
        .init(x: 418, y: 614), .init(x: 405, y: 368), .init(x: 738, y: 355),
        .init(x: 765, y: 701), .init(x: 318, y: 734), .init(x: 285, y: 268),
    ]
    /// Tight bounding box of the points, in source coordinates.
    static let minX: CGFloat = 285
    static let maxX: CGFloat = 765
    static let minY: CGFloat = 268
    static let maxY: CGFloat = 734
    /// ~half stroke width, keeps the round caps inside the cropped box.
    static let pad: CGFloat = 26
    static let stroke: CGFloat = 46   // source-coordinate stroke width used by the icon

    static var width: CGFloat { (maxX - minX) + pad * 2 }
    static var height: CGFloat { (maxY - minY) + pad * 2 }
}

/// The Screenshot Buddy spiral mark, drawn as line-art (from icon-kit/mark.svg).
struct BuddyMark: Shape {
    func path(in rect: CGRect) -> Path {
        let g = BuddyGlyph.self
        let s = min(rect.width / g.width, rect.height / g.height)
        // Center the glyph in the frame.
        let offX = rect.minX + (rect.width - g.width * s) / 2
        let offY = rect.minY + (rect.height - g.height * s) / 2
        var p = Path()
        for (i, pt) in g.pts.enumerated() {
            let scaled = CGPoint(x: offX + (pt.x - g.minX + g.pad) * s,
                                 y: offY + (pt.y - g.minY + g.pad) * s)
            if i == 0 { p.move(to: scaled) } else { p.addLine(to: scaled) }
        }
        return p
    }
}

extension BuddyMark {
    /// A template NSImage of the mark, cropped tight to its outline so it fills
    /// the full menu-bar height (like the Evernote/Dropbox glyphs).
    static func menuBarImage(height: CGFloat = 18) -> NSImage {
        let g = BuddyGlyph.self
        let scale = height / g.height
        let size = NSSize(width: g.width * scale, height: g.height * scale)

        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath()
        path.lineWidth = g.stroke * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for (i, pt) in g.pts.enumerated() {
            // Flip Y (AppKit origin is bottom-left) and shift into the tight box.
            let x = (pt.x - g.minX + g.pad) * scale
            let y = (g.height - (pt.y - g.minY + g.pad)) * scale
            let p = NSPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        NSColor.black.setStroke()
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

// MARK: - Button styles

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Capsule().fill(Theme.pill))
            .shadow(color: Theme.accent1.opacity(0.45), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}
