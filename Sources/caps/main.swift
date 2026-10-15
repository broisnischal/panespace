import AppKit
import ApplicationServices
import CapsCore

let help = """
caps — Caps Lock as a programmable key, per app

USAGE
  caps                       run (menu bar app)
  caps check-config [path]   parse a config and print warnings

Hold Caps Lock and press a key: bindings for the frontmost app run first, then global ones;
anything else goes to panespace as Caps+key. Tap Caps alone for Escape.
Config: \(capsConfigURL().path)
"""

final class AppDelegate: NSObject, NSApplicationDelegate {
    let caps = Caps()
    private var waitTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) { return caps.start() }
        log("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
        waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            self?.caps.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { caps.stop() }
}

var signalSources: [DispatchSourceSignal] = []

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case nil:
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: "app.panespace.Caps")
        .filter { $0.processIdentifier != getpid() }
    if !others.isEmpty {
        fputs("caps: already running\n", stderr)
        exit(1)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            delegate.caps.stop()
            exit(0)
        }
        src.resume()
        signalSources.append(src)
    }
    app.run()
case "check-config":
    let url = args.count > 1 ? URL(fileURLWithPath: args[1]) : capsConfigURL()
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("caps: cannot read \(url.path)\n", stderr)
        exit(1)
    }
    let c = CapsConfig.parse(text)
    print("\(url.path): \(c.global.count) global bindings, \(c.apps.count) app layers, tap: \(c.tap.map { "\($0)" } ?? "none")")
    c.warnings.forEach { print("warning: \($0)") }
    exit(c.warnings.isEmpty ? 0 : 2)
default:
    print(help)
}
