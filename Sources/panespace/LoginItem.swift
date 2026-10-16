import Foundation

/// "Open at Login": the per-user launchd agent that `make login-item` also installs. Its KeepAlive
/// relaunches panespace after a crash, so windows parked on hidden workspaces never stay stranded.
enum LoginItem {
    static let label = "app.panespace.Panespace"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// Takes effect at the next login. Turning it off only removes the agent; it never stops the running
    /// panespace (`launchctl bootout` would).
    static func set(_ on: Bool) throws {
        guard on else {
            if isEnabled { try FileManager.default.removeItem(at: plistURL) }
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? CommandLine.arguments[0]],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "StandardErrorPath": home.appendingPathComponent("Library/Logs/panespace.log").path,
            "AssociatedBundleIdentifiers": [label],  // System Settings → Login Items shows it as Panespace
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL, options: .atomic)
    }
}
