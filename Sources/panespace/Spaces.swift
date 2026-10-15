import AppKit

/// Read-only view of macOS Spaces through the window server's private (but long-stable) CGS calls,
/// loaded with dlsym so a missing symbol just disables the checks.
///
/// panespace replaces Spaces with its own workspaces: macOS hides windows on other Spaces from window
/// managers, so a second desktop or an app in native full screen breaks tiling. This lets panespace notice.
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64

    private static let api: (MainConnection, CopyDisplaySpaces, CopySpacesForWindows, ActiveSpace)? = {
        let h = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let a = dlsym(h, "CGSMainConnectionID"), let b = dlsym(h, "CGSCopyManagedDisplaySpaces"),
              let c = dlsym(h, "CGSCopySpacesForWindows"), let d = dlsym(h, "CGSGetActiveSpace") else { return nil }
        return (unsafeBitCast(a, to: MainConnection.self), unsafeBitCast(b, to: CopyDisplaySpaces.self),
                unsafeBitCast(c, to: CopySpacesForWindows.self), unsafeBitCast(d, to: ActiveSpace.self))
    }()

    struct Summary: Equatable {
        /// Desktops beyond the first on any display.
        var extraDesktops = 0
        /// Apps in macOS native full screen (each one is its own Space).
        var fullscreenApps = 0
        /// The Space you're looking at is a native full-screen one.
        var activeIsFullscreen = false
        var activeSpace: UInt64 = 0
        /// (window, app pid) of every app in native full screen.
        var fullscreenWindows: [FullscreenWindow] = []
    }

    struct FullscreenWindow: Equatable {
        let window: CGWindowID
        let pid: pid_t
    }

    static func summary() -> Summary {
        guard let (conn, copy, _, active) = api, let displays = copy(conn())?.takeRetainedValue() as? [[String: Any]] else {
            return Summary()
        }
        var s = Summary()
        s.activeSpace = active(conn())
        for d in displays {
            let spaces = d["Spaces"] as? [[String: Any]] ?? []
            let desktops = spaces.filter { ($0["type"] as? Int) == 0 }.count
            s.extraDesktops += max(0, desktops - 1)
            for fs in spaces where (fs["type"] as? Int) == 4 {
                s.fullscreenApps += 1
                if let w = (fs["fs_wid"] as? NSNumber)?.uint32Value, let pid = (fs["pid"] as? NSNumber)?.int32Value {
                    s.fullscreenWindows.append(FullscreenWindow(window: w, pid: pid))
                }
            }
            if let cur = d["Current Space"] as? [String: Any], (cur["ManagedSpaceID"] as? UInt64) == s.activeSpace
                || (cur["ManagedSpaceID"] as? Int).map(UInt64.init) == s.activeSpace {
                s.activeIsFullscreen = (cur["type"] as? Int) == 4
            }
        }
        return s
    }

    /// Spaces a window is on (empty if unknown).
    static func spaces(of window: CGWindowID) -> [UInt64] {
        guard let (conn, _, forWindows, _) = api,
              let r = forWindows(conn(), 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return r.map(\.uint64Value)
    }
}
