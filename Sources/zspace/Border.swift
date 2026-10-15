import AppKit

/// Click-through overlay that outlines the focused window, like i3's focused border.
final class FocusBorder {
    private let window: NSWindow
    private let view = BorderView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
    }

    /// `frame` in Accessibility coordinates.
    func show(around frame: CGRect, width: CGFloat, radius: CGFloat, color: String) {
        guard width > 0 else { return hide() }
        let outer = frame.insetBy(dx: -width, dy: -width)
        let h = NSScreen.screens.first?.frame.height ?? 0
        view.width = width
        view.radius = radius > 0 ? radius + width : 0
        view.color = NSColor(hex: color) ?? .systemBlue
        view.needsDisplay = true
        window.setFrame(NSRect(x: outer.minX, y: h - outer.maxY, width: outer.width, height: outer.height), display: true)
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }
}

private final class BorderView: NSView {
    var width: CGFloat = 2
    var radius: CGFloat = 12
    var color = NSColor.systemBlue

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: width / 2, dy: width / 2)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (v << 8) | 0xFF : v
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}
