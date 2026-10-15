import AppKit
import CapsCore
import ZSpaceCore

/// The built-in `do …` actions. Main thread.
enum Specials {
    private static var keepAwake: Process?

    static func run(_ s: Special, caps: Caps) {
        switch s {
        // Media and hardware keys go through the same path as the real keys, so macOS shows its own HUD.
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .brightnessUp: mediaKey(2)
        case .brightnessDown: mediaKey(3)
        case .keyboardLightUp: mediaKey(21)
        case .keyboardLightDown: mediaKey(22)

        case .screenshot: caps.press("ctrl+cmd+shift+4")  // area → clipboard
        case .screenshotFile: caps.press("cmd+shift+4")
        case .screenshotUI: caps.press("cmd+shift+5")
        case .spotlight: caps.press("cmd+space")
        case .emoji: caps.press("ctrl+cmd+space")

        case .lock:
            if let lock = lockScreen { _ = lock() } else { caps.press("ctrl+cmd+q") }
        case .sleepDisplay: run("/usr/bin/pmset", ["displaysleepnow"])
        case .sleep: run("/usr/bin/pmset", ["sleepnow"])
        case .darkMode:
            run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])

        case .showDesktop: run(missionControl, ["1"])
        case .missionControl: run(missionControl, [])
        case .appWindows: run(missionControl, ["2"])

        case .keepAwake:
            if let p = keepAwake, p.isRunning {
                p.terminate()
                keepAwake = nil
                log("keep-awake off")
            } else {
                keepAwake = run("/usr/bin/caffeinate", ["-di"])
                log("keep-awake on")
            }

        case .pastePlain:
            let pb = NSPasteboard.general
            guard let text = pb.string(forType: .string) else { return }
            pb.clearContents()
            pb.setString(text, forType: .string)
            caps.press("cmd+v")

        case .quitApp: NSWorkspace.shared.frontmostApplication?.terminate()
        case .forceQuitApp: NSWorkspace.shared.frontmostApplication?.forceTerminate()
        case .hideApp: NSWorkspace.shared.frontmostApplication?.hide()
        case .hideOthers:
            let front = NSWorkspace.shared.frontmostApplication
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app != front { app.hide() }

        case .cheatsheet: caps.showCheatSheet()
        case .editConfig: caps.editConfig()
        case .reloadConfig: caps.loadConfig()
        }
    }

    private static let missionControl = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"

    /// login.framework's lock, the same call the menu bar's Lock Screen uses. Falls back to ⌃⌘Q.
    private static let lockScreen: (@convention(c) () -> Int32)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let p = dlsym(h, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(p, to: (@convention(c) () -> Int32).self)
    }()

    /// NX_KEYTYPE_* system-defined key, as the hardware media keys send it.
    private static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], env: [String: String]? = nil) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env { p.environment = env }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            return p
        } catch {
            log("\(path) failed: \(error)")
            return nil
        }
    }

    static func stop() { keepAwake?.terminate() }
}
