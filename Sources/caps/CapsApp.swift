import AppKit
import CapsCore
import MacKit
import PanespaceCore

private let logTime = ISO8601DateFormatter()

func log(_ s: String) {
    FileHandle.standardError.write(Data("\(logTime.string(from: Date())) caps: \(s)\n".utf8))
}

func capsConfigURL() -> URL {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    return base.appendingPathComponent("caps/config")
}

/// Runs everything: config (with live reload), the key hook, actions and the menu bar item.
final class Caps: NSObject, NSMenuDelegate {
    let configURL = capsConfigURL()
    private(set) var config = CapsConfig()
    private let tap = CapsTap()
    private let overlay = Overlay()
    /// panespace's bindings for the cheat sheet; refreshed in the background each time Caps goes down.
    private var panespaceBindings: [(KeyCombo, String)] = []
    private var item: NSStatusItem?
    private var watcher: DispatchSourceFileSystemObject?
    private let ipcQueue = DispatchQueue(label: "caps.panespace")

    func start() {
        loadConfig()
        CapsLock.enable()
        tap.onAction = { [unowned self] in perform($0) }
        tap.onCapsDown = { [unowned self] in refreshPanespaceBindings() }
        tap.onHold = { [unowned self] in
            switch config.hold {
            case .cheatsheet: showCheatSheet()
            case .blur: overlay.show(sections: nil, app: "")
            case .action(let a): perform(a)
            case .none: break
            }
        }
        tap.onCapsUp = { [unowned self] in overlay.hide() }
        tap.onKeyWhileHeld = { [unowned self] in overlay.hide() }  // you know what you want: show the result
        guard tap.start() else {
            log("could not create the event tap (is Accessibility granted?)")
            return
        }
        let ws = NSWorkspace.shared
        if let app = ws.frontmostApplication { tap.setFrontApp(name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "") }
        ws.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                          queue: .main) { [unowned self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            tap.setFrontApp(name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "")
        }
        installMenu()
        watchConfig()
        log("started; config \(configURL.path)")
    }

    func stop() {
        Specials.stop()
        CapsLock.disable()
    }

    // MARK: Cheat sheet

    func showCheatSheet() {
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.localizedName ?? "this app"
        let sections = CheatSheet.sections(config: config, app: app, bundleID: front?.bundleIdentifier ?? "",
                                           panespace: panespaceBindings)
        overlay.show(sections: sections, app: app)
    }

    private func refreshPanespaceBindings() {
        ipcQueue.async { [weak self] in
            guard let resp = IPC.send(type: "get_bindings", payload: ""),
                  let rows = try? JSONSerialization.jsonObject(with: Data(resp.utf8)) as? [[String: String]] else { return }
            let parsed = rows.compactMap { r -> (KeyCombo, String)? in
                guard let k = r["key"].flatMap({ KeyCombo.parse($0) }), let c = r["command"] else { return nil }
                return (k, c)
            }
            DispatchQueue.main.async { self?.panespaceBindings = parsed }
        }
    }

    /// Sends a keystroke ("cmd+shift+4") tagged as Caps's own.
    func press(_ spec: String) {
        guard let k = KeyCombo.parse(spec) else { return }
        tap.post(k, down: true)
        tap.post(k, down: false)
    }

    // MARK: Config

    func loadConfig() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configURL.path) {
            try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? DefaultCapsConfig.text.write(to: configURL, atomically: true, encoding: .utf8)
        }
        config = CapsConfig.parse((try? String(contentsOf: configURL, encoding: .utf8)) ?? DefaultCapsConfig.text)
        tap.update(config)
        if !config.warnings.isEmpty { log("config warnings:\n  " + config.warnings.joined(separator: "\n  ")) }
    }

    /// Reloads on save. Editors often replace the file, so re-arm on rename/delete.
    private func watchConfig() {
        watcher?.cancel()
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [unowned self] in
            let replaced = !src.data.isDisjoint(with: [.rename, .delete])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.loadConfig()
                log("config reloaded")
                if replaced { self.watchConfig() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    // MARK: Actions

    private func perform(_ a: CapsAction) {
        switch a {
        case .key(let k):
            tap.post(k, down: true)
            tap.post(k, down: false)
        case .open(let name):
            let front = NSWorkspace.shared.frontmostApplication
            if let front, [front.localizedName, front.bundleIdentifier].contains(where: { $0?.caseInsensitiveCompare(name) == .orderedSame }) {
                front.hide()  // already in front: Caps+key again puts it away
            } else {
                run("/usr/bin/open", name.contains(".") && !name.contains(" ") && !name.hasSuffix(".app") ? ["-b", name] : ["-a", name])
            }
        case .exec(let cmd):
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            run("/bin/sh", ["-c", cmd], env: env)
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .text(let t):
            tap.type(t)
        case .panespace(let cmd):
            ipcQueue.async {
                if IPC.send(type: "run_command", payload: cmd) == nil { log("panespace isn't running (\(cmd))") }
            }
        case .shortcut(let name):
            run("/usr/bin/shortcuts", ["run", name])
        case .special(let s):
            Specials.run(s, caps: self)
        case .nothing:
            break
        }
    }

    private func run(_ path: String, _ args: [String], env: [String: String]? = nil) {
        Specials.run(path, args, env: env)
    }

    // MARK: Menu bar

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: "Caps")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon?.isTemplate = true
        item.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        self.item = item
    }

    /// Built when opened: shows what Caps does in the app you're in.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? "this app"
        let b = config.bindings(app: name, bundleID: front?.bundleIdentifier ?? "")
        func section(_ title: String, _ rows: [CapsConfig.Entry]) {
            guard !rows.isEmpty else { return }
            if #available(macOS 14.0, *) { menu.addItem(.sectionHeader(title: title)) } else {
                let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                h.isEnabled = false
                menu.addItem(h)
            }
            for (combo, action, note) in rows {
                let i = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let t = NSMutableAttributedString(string: "⇪ " + CheatSheet.keys(combo),
                                                  attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)])
                t.append(NSAttributedString(string: "   " + (note ?? CheatSheet.label(action)), attributes: [
                    .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
                ]))
                i.attributedTitle = t
                i.isEnabled = false
                menu.addItem(i)
            }
            menu.addItem(.separator())
        }
        section("In \(name)", b.app)
        section("Everywhere", b.global)
        if b.app.isEmpty && b.global.isEmpty {
            let i = NSMenuItem(title: "No bindings yet — Caps+key goes to panespace", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
            menu.addItem(.separator())
        }
        if !config.warnings.isEmpty {
            let w = NSMenuItem(title: "Config Warnings (\(config.warnings.count))…", action: #selector(showWarnings), keyEquivalent: "")
            w.target = self
            menu.addItem(w)
        }
        for (title, sel) in [("Edit Config…", #selector(editConfig)), ("Reload Config", #selector(reload)),
                             ("Quit Caps (gives Caps Lock back)", #selector(quit))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
    }

    @objc func editConfig() {
        NSWorkspace.shared.open([configURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func reload() { loadConfig() }

    @objc private func showWarnings() {
        let alert = NSAlert()
        alert.messageText = "Caps config warnings"
        alert.informativeText = config.warnings.joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        stop()
        exit(0)
    }
}
