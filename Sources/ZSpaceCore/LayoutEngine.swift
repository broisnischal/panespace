import CoreGraphics

public struct Gaps: Equatable {
    public var inner: CGFloat = 0
    public var top: CGFloat = 0
    public var bottom: CGFloat = 0
    public var left: CGFloat = 0
    public var right: CGFloat = 0
    public init() {}
}

enum LayoutEngine {
    /// Frames for every tiled window of `ws` on `monitor` (plus a fullscreen window, if any).
    /// Also records each node's rect for geometry-based commands.
    static func layout(_ ws: Workspace, on monitor: Monitor, config: Config) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        let tiledCount = ws.root.windows.count
        let g = config.smartGaps && tiledCount <= 1 ? Gaps() : config.gaps
        let v = monitor.visibleFrame
        let area = CGRect(x: v.minX + g.left, y: v.minY + g.top,
                          width: max(1, v.width - g.left - g.right), height: max(1, v.height - g.top - g.bottom))
        place(ws.root, area, ws: ws, inner: g.inner, padding: config.accordionPadding, into: &out)
        if let fs = ws.fullscreen { out[fs.id] = v }
        return out
    }

    private static func place(_ n: Node, _ r: CGRect, ws: Workspace, inner: CGFloat, padding: CGFloat,
                              into out: inout [WindowID: CGRect]) {
        n.rect = r
        if let w = n as? WindowNode {
            out[w.id] = r
            return
        }
        guard let c = n as? Container, !c.children.isEmpty else { return }
        let k = c.children.count
        let horizontal = c.layout.orientation == .horizontal

        if c.layout.isSplit {
            let length = (horizontal ? r.width : r.height) - inner * CGFloat(k - 1)
            let total = c.children.reduce(0) { $0 + max($1.weight, 0.0001) }
            var pos = horizontal ? r.minX : r.minY
            for (i, child) in c.children.enumerated() {
                let end = horizontal ? r.maxX : r.maxY
                let size = i == k - 1 ? end - pos : (length * max(child.weight, 0.0001) / total).rounded()
                let cr = horizontal
                    ? CGRect(x: pos, y: r.minY, width: size, height: r.height)
                    : CGRect(x: r.minX, y: pos, width: r.width, height: size)
                place(child, cr, ws: ws, inner: inner, padding: padding, into: &out)
                pos += size + inner
            }
            return
        }

        // tabbed / stacking: accordion. Every child covers the container, offset so neighbours' edges peek out.
        let focused = ws.mostRecentChild(of: c).flatMap { f in c.children.firstIndex { $0 === f } } ?? 0
        for (i, child) in c.children.enumerated() {
            let (lead, trail): (CGFloat, CGFloat)
            if k == 1 { (lead, trail) = (0, 0) }
            else if i == 0 { (lead, trail) = (0, padding) }
            else if i == k - 1 { (lead, trail) = (padding, 0) }
            else if i == focused - 1 { (lead, trail) = (0, 2 * padding) }
            else if i == focused + 1 { (lead, trail) = (2 * padding, 0) }
            else { (lead, trail) = (padding, padding) }
            let cr = horizontal
                ? CGRect(x: r.minX + lead, y: r.minY, width: r.width - lead - trail, height: r.height)
                : CGRect(x: r.minX, y: r.minY + lead, width: r.width, height: r.height - lead - trail)
            place(child, cr, ws: ws, inner: inner, padding: padding, into: &out)
        }
    }
}
