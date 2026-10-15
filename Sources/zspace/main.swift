import AppKit
import MacKit
import ApplicationServices
import ZSpaceCore

let zspaceVersion = "0.1.0"

let help = """
zspace \(zspaceVersion) — i3-style tiling window manager for macOS

USAGE
  zspace                      start the window manager (foreground)
  zspace msg <command>        run an i3 command, e.g. zspace msg focus left
  zspace msg -t <type>        query: get_tree, get_workspaces, get_bindings, get_binding_modes, get_config, get_version
  zspace <command>            shorthand for `zspace msg <command>`
  zspace list-windows         show every window and how zspace classifies it (for writing rules)
  zspace check-config [path]  parse a config and print warnings
  zspace init-config          write the default config if none exists, print its path

Config: \(configURL().path)
"""

func configURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    return base.appendingPathComponent("zspace/config")
}

func send(_ type: String, _ payload: String) -> Never {
    guard let resp = IPC.send(type: type, payload: payload) else {
        fputs("zspace: not running (no socket at \(IPC.socketPath))\n", stderr)
        exit(1)
    }
    print(resp)
    exit(resp.contains("\"success\" : false") ? 2 : 0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var wm: WindowManager?
    private var waitItem: NSStatusItem?
    private var waitTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) { return start() }
        log("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "zspace ⚠︎"
        let menu = NSMenu()
        menu.addItem(withTitle: "Grant Accessibility access…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        waitItem = item
        waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            if let item = self?.waitItem { NSStatusBar.system.removeStatusItem(item) }
            self?.start()
        }
    }

    @objc func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func start() {
        let wm = WindowManager(configURL: configURL())
        self.wm = wm
        wm.start()
    }

    func applicationWillTerminate(_ notification: Notification) { wm?.restoreAllWindows() }
}

var signalSources: [DispatchSourceSignal] = []

func runDaemon() -> Never {
    if IPC.send(type: "get_version", payload: "") != nil {
        fputs("zspace: already running\n", stderr)
        exit(0)  // not a failure: launchd's KeepAlive must not keep relaunching a duplicate
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            if let wm = delegate.wm { wm.shutdown() }
            exit(0)
        }
        src.resume()
        signalSources.append(src)
    }
    app.run()
    exit(0)
}

func listWindows() -> Never {
    guard AXIsProcessTrusted() else {
        fputs("zspace: this terminal needs Accessibility permission to read windows\n", stderr)
        exit(1)
    }
    let server = windowServerSnapshot()
    let start = Date()
    var rows: [[String]] = [["ID", "KIND", "APP", "BUNDLE ID", "SUBROLE", "FRAME", "TITLE"]]
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let el = AXUIElement.app(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 1)
        for w in el.windows {
            let id = w.windowID
            let kind = id.map { _ in classify(w, bundleID: app.bundleIdentifier ?? "", layer: server[id!]?.layer) } ?? .ignore
            let f = w.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "?"
            rows.append([id.map(String.init) ?? "-", w.isMinimized ? "minimized" : "\(kind)",
                         app.localizedName ?? "?", app.bundleIdentifier ?? "", w.subrole ?? "", f,
                         String(w.title.prefix(50))])
        }
    }
    let widths = rows[0].indices.map { i in rows.map { $0[i].count }.max()! }
    for r in rows {
        print(r.enumerated().map { i, c in c.padding(toLength: widths[i], withPad: " ", startingAt: 0) }.joined(separator: "  "))
    }
    print(String(format: "\n%d windows read in %.0f ms", rows.count - 1, Date().timeIntervalSince(start) * 1000))
    exit(0)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil, "start": runDaemon()
case "msg":
    var a = Array(args.dropFirst())
    var type = "run_command"
    if a.first == "-t", a.count >= 2 {
        type = a[1]
        a.removeFirst(2)
    }
    send(type, a.joined(separator: " "))
case "list-windows": listWindows()
case "check-config":
    let url = args.count > 1 ? URL(fileURLWithPath: args[1]) : configURL()
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("zspace: cannot read \(url.path)\n", stderr)
        exit(1)
    }
    let c = Config.parse(text)
    let n = c.modes.values.reduce(0) { $0 + $1.count }
    print("\(url.path): \(n) bindings in \(c.modes.count) mode(s), \(c.rules.count) rules")
    c.warnings.forEach { print("warning: \($0)") }
    exit(c.warnings.isEmpty ? 0 : 2)
case "init-config":
    let url = configURL()
    if !FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DefaultConfig.text.write(to: url, atomically: true, encoding: .utf8)
    }
    print(url.path)
case "help", "-h", "--help": print(help)
case "version", "-v", "--version": print(zspaceVersion)
default: send("run_command", args.joined(separator: " "))
}
