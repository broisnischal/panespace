import CoreGraphics
import Foundation

/// Pure math for layout animations: easing, interpolation, and which way a workspace switch slides.
public enum Motion {
    /// Ease-out (quartic): a quick start and a gentle landing.
    public static func ease(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return 1 - pow(1 - c, 4)
    }

    /// The frame `p` of the way from `a` to `b`, on whole points so windows don't shimmer.
    public static func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        let k = CGFloat(p)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { (x + (y - x) * k).rounded() }
        return CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY), width: mix(a.width, b.width), height: mix(a.height, b.height))
    }

    public struct Slide: Equatable {
        /// Added to a window's target to get where it starts when it slides in.
        public var enter: CGVector
        /// Added to a window's current frame to get where it slides out to.
        public var exit: CGVector
    }

    /// How windows travel when `monitor` switches workspace: sideways like Spaces when nothing sits beside it,
    /// up from below when a display is beside it, not at all when it's boxed in (they'd cross another display).
    public static func slide(on monitor: Monitor, among monitors: [Monitor], forward: Bool) -> Slide? {
        let f = monitor.frame
        let others = monitors.filter { $0.id != monitor.id }.map(\.frame)
        // Inset so displays that merely touch this one's edge don't count.
        func free(_ r: CGRect) -> Bool { !others.contains { $0.intersects(r.insetBy(dx: 1, dy: 1)) } }
        if free(f.offsetBy(dx: -f.width, dy: 0)) && free(f.offsetBy(dx: f.width, dy: 0)) {
            let d = forward ? f.width : -f.width
            return Slide(enter: CGVector(dx: d, dy: 0), exit: CGVector(dx: -d, dy: 0))
        }
        if free(f.offsetBy(dx: 0, dy: f.height)) {
            return Slide(enter: CGVector(dx: 0, dy: f.height), exit: CGVector(dx: 0, dy: f.height))
        }
        return nil
    }

    /// Whether going from workspace `a` to `b` moves forward: by number when both have one, else by `order`.
    public static func isForward(from a: String, to b: String, order: [String]) -> Bool {
        if let x = Int(a), let y = Int(b) { return y > x }
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return true }
        return j > i
    }
}
