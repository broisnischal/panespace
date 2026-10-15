import Foundation

/// Immersive mode (Omarchy-style): the macOS menu bar and Dock auto-hide, so tiles and fullscreen
/// windows use the whole display. Changes the real macOS settings through System Events (asks for
/// Automation permission once) and puts back what it found when panespace quits.
final class MacChrome {
    private(set) var isImmersive: Bool
    private var original: (menuBar: Bool, dock: Bool)?

    init() { isImmersive = MacChrome.menuBarHidden() && MacChrome.dockHidden() }

    static func menuBarHidden() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["_HIHideMenuBar"] as? Bool) ?? false
    }

    static func dockHidden() -> Bool { UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false }

    func set(_ on: Bool) {
        guard on != isImmersive else { return }
        if original == nil { original = (MacChrome.menuBarHidden(), MacChrome.dockHidden()) }
        let target: (Bool, Bool)
        if on {
            target = (true, true)
        } else if let o = original, !(o.menuBar && o.dock) {
            target = o
        } else {
            target = (false, false)
        }
        isImmersive = on
        write(menuBar: target.0, dock: target.1, wait: false)
    }

    /// Called on quit: leave the user's Mac as panespace found it.
    func restore() {
        guard let o = original else { return }
        write(menuBar: o.menuBar, dock: o.dock, wait: true)
        original = nil
    }

    private func write(menuBar: Bool, dock: Bool, wait: Bool) {
        let script = """
        tell application "System Events" to tell dock preferences
            set autohide menu bar to \(menuBar)
            set autohide to \(dock)
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        p.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            log("immersive: System Events refused (\(msg.trimmingCharacters(in: .whitespacesAndNewlines))). "
                + "Allow Panespace under System Settings → Privacy & Security → Automation.")
        }
        do {
            try p.run()
            if wait { p.waitUntilExit() }
        } catch {
            log("immersive: could not run osascript: \(error)")
        }
    }
}
