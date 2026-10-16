import Foundation

/// Immersive mode (Omarchy-style): the macOS menu bar auto-hides, so tiles and fullscreen windows use the
/// whole display. Changes the real macOS setting through System Events (asks for Automation permission once)
/// and puts back what it found when panespace quits. The Dock is never touched: it follows its own macOS
/// setting (System Settings → Desktop & Dock → "Automatically hide and show the Dock").
final class MacChrome {
    private(set) var isImmersive: Bool
    private var original: Bool?

    init() { isImmersive = MacChrome.menuBarHidden() }

    static func menuBarHidden() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["_HIHideMenuBar"] as? Bool) ?? false
    }

    func set(_ on: Bool) {
        guard on != isImmersive else { return }
        if original == nil { original = MacChrome.menuBarHidden() }
        isImmersive = on
        write(menuBarHidden: on, wait: false)
    }

    /// Called on quit: leave the user's Mac as panespace found it.
    func restore() {
        guard let o = original else { return }
        write(menuBarHidden: o, wait: true)
        original = nil
    }

    private func write(menuBarHidden: Bool, wait: Bool) {
        let script = """
        tell application "System Events" to tell dock preferences
            set autohide menu bar to \(menuBarHidden)
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
