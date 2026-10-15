import CoreGraphics
import Foundation

/// Caps Lock as a modifier. macOS's built-in `hidutil` remaps Caps Lock to F18 (a key no app uses);
/// zspace and Caps treat a held F18 as the `caps` modifier. The mapping lasts until reboot. Both apps
/// can hold it at once: an owners file (live PIDs) decides when Caps Lock is given back. Main thread only.
public enum CapsLock {
    public static let f18KeyCode: CGKeyCode = 0x4F
    /// `eventSourceUserData` on a key/mouse event Caps passed on while Caps Lock is held.
    public static let heldTag: Int64 = 0x5A53_4341_5053_0001
    /// `eventSourceUserData` on an event Caps generated itself (a remapped key); zspace leaves these alone.
    public static let syntheticTag: Int64 = 0x5A53_4341_5053_0002

    private static let capsUsage: UInt64 = 0x7_0000_0039  // keyboard page, Caps Lock
    private static let f18Usage: UInt64 = 0x7_0000_006D   // keyboard page, F18
    private static let ownersPath = "/tmp/zspace-\(getuid())-capslock-owners"

    /// The (remapped) Caps key is down right now, per the keyboard hardware state. Reliable even though
    /// the key's own events are swallowed, and can't get stuck the way tracking key-up events can.
    public static var isPhysicallyDown: Bool { CGEventSource.keyState(.hidSystemState, key: f18KeyCode) }

    public static func enable() {
        writeOwners(liveOwners().union([getpid()]))
        let current = read()
        guard !current.contains(where: { $0.src == capsUsage && $0.dst == f18Usage }) else { return }
        write(current.filter { $0.src != capsUsage } + [(capsUsage, f18Usage)])
    }

    /// Gives Caps Lock back once no other running app still uses it.
    public static func disable() {
        let owners = liveOwners()
        guard owners.contains(getpid()) else { return }
        let rest = owners.subtracting([getpid()])
        writeOwners(rest)
        guard rest.isEmpty else { return }
        write(read().filter { !($0.src == capsUsage && $0.dst == f18Usage) })
    }

    private static func liveOwners() -> Set<pid_t> {
        let text = (try? String(contentsOfFile: ownersPath, encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").compactMap { pid_t($0) }.filter { kill($0, 0) == 0 })
    }

    private static func writeOwners(_ owners: Set<pid_t>) {
        let text = owners.map(String.init).joined(separator: "\n")
        FileManager.default.createFile(atPath: ownersPath, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
    }

    private static func hidutil(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            FileHandle.standardError.write(Data("hidutil failed: \(error)\n".utf8))
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses `hidutil property --get UserKeyMapping` ("( { HIDKeyboardModifierMappingDst = …; Src = …; } )").
    private static func read() -> [(src: UInt64, dst: UInt64)] {
        let text = hidutil(["property", "--get", "UserKeyMapping"])
        var out: [(UInt64, UInt64)] = []
        for block in text.components(separatedBy: "}") {
            func value(_ key: String) -> UInt64? {
                guard let r = block.range(of: key + " = ") else { return nil }
                return UInt64(block[r.upperBound...].prefix { $0.isNumber })
            }
            if let s = value("HIDKeyboardModifierMappingSrc"), let d = value("HIDKeyboardModifierMappingDst") {
                out.append((s, d))
            }
        }
        return out
    }

    private static func write(_ mapping: [(src: UInt64, dst: UInt64)]) {
        let items = mapping.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}" }
        _ = hidutil(["property", "--set", "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"])
    }
}
