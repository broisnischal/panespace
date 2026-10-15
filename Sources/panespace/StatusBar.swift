import AppKit
import CoreText
import PanespaceCore

/// Menu bar indicator. Drawn as a template image so macOS tints it exactly like its own icons
/// (light/dark, Tahoe's translucent menu bar). Clicking opens a menu of workspaces and settings.
final class StatusBar: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private weak var manager: WindowManager?
    private var renderedKey = ""

    func install(manager: WindowManager) {
        self.manager = manager
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        self.item = item
    }

    func update(model: Model, secureInput: Bool, spacesWarning: String?) {
        let slots = model.sortedWorkspaces.filter { !$0.isEmpty || model.isVisible($0) }.map { ws in
            WorkspaceIcon.Slot(label: WorkspaceIcon.label(ws.name),
                               style: ws === model.focusedWorkspace ? .focused : model.isVisible(ws) ? .visible : .occupied)
        }
        let mode = model.mode == "default" ? nil : model.mode
        let look = WorkspaceIcon.Look(rawValue: model.config.workspaceIndicator) ?? .number
        let warn = spacesWarning != nil
        let key = "\(slots)|\(mode ?? "")|\(secureInput)|\(look)|\(warn)"
        guard key != renderedKey, let button = item?.button else { return }  // re-render only on change
        renderedKey = key
        button.image = WorkspaceIcon.render(slots: slots, mode: mode, secureInput: secureInput, warning: warn, look: look)
        let focused = model.focusedWorkspace.name
        button.setAccessibilityLabel("panespace, workspace \(focused)" + (mode.map { ", \($0) mode" } ?? ""))
        button.toolTip = spacesWarning
            ?? (secureInput ? "Secure Input is on (a password field is focused), so macOS is withholding keystrokes from panespace."
                            : "panespace — workspace \(focused)")
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let manager else { return }
        let model = manager.model
        if let warning = manager.spacesWarning {
            let i = menuItem("⚠︎ Some windows can't be tiled — how to fix…", #selector(showSpacesHelp))
            i.toolTip = warning
            menu.addItem(i)
            menu.addItem(.separator())
        }
        menu.addItem(header("Workspaces"))
        for ws in model.sortedWorkspaces where !ws.isEmpty || model.isVisible(ws) {
            var apps: [String] = []
            for w in ws.allWindows where !apps.contains(w.info.app) { apps.append(w.info.app) }
            let item = NSMenuItem(title: ws.name, action: #selector(switchWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ws.name
            item.state = ws === model.focusedWorkspace ? .on : .off
            let title = NSMutableAttributedString(string: ws.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            var detail = apps.isEmpty ? "empty" : apps.joined(separator: ", ")
            if model.monitors.count > 1, let m = model.monitor(ws.monitorID) { detail += "  ·  \(m.name)" }
            title.append(NSAttributedString(string: "    " + detail, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            item.attributedTitle = title
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let immersive = menuItem("Immersive Mode", #selector(toggleImmersive), shortcut: "immersive toggle")
        immersive.state = manager.chrome.isImmersive ? .on : .off
        immersive.toolTip = "Auto-hide the menu bar and Dock so windows use the whole screen"
        menu.addItem(immersive)
        menu.addItem(.separator())
        menu.addItem(menuItem("Reload Config", #selector(reload), shortcut: "reload"))
        menu.addItem(menuItem("Edit Config…", #selector(editConfig)))
        if !manager.configWarnings.isEmpty {
            menu.addItem(menuItem("Config Warnings (\(manager.configWarnings.count))…", #selector(showWarnings)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit panespace", #selector(quit), shortcut: "exit"))
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    /// Shows the user's actual binding for `command` (from the config) as the item's shortcut hint.
    private func menuItem(_ title: String, _ action: Selector, shortcut command: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        if let command, let combo = manager?.model.config.modes["default"]?.first(where: { $0.value == command })?.key,
           let name = combo.keyName, name.count == 1, !combo.modifiers.contains(.caps) {
            i.keyEquivalent = name
            var m: NSEvent.ModifierFlags = []
            if combo.modifiers.contains(.control) { m.insert(.control) }
            if combo.modifiers.contains(.option) { m.insert(.option) }
            if combo.modifiers.contains(.shift) { m.insert(.shift) }
            if combo.modifiers.contains(.command) { m.insert(.command) }
            i.keyEquivalentModifierMask = m
        }
        return i
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        manager?.runCommand("workspace \"\(name.replacingOccurrences(of: "\"", with: "\\\""))\"")
    }

    @objc private func showSpacesHelp() { manager?.showDesktopsAlert() }

    @objc private func toggleImmersive() { manager?.runCommand("immersive toggle") }
    @objc private func reload() { manager?.reload() }

    @objc private func editConfig() {
        guard let url = manager?.configURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showWarnings() {
        let alert = NSAlert()
        alert.messageText = "panespace config warnings"
        alert.informativeText = manager?.configWarnings.joined(separator: "\n") ?? ""
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { manager?.shutdown() }
}

/// Renders the workspace indicator as a template image (macOS tints it like its own icons).
///   segmented (default)  one capsule control; the focused workspace is a solid pill, number cut out
///   dots                 focused workspace as a numbered pill, the others as small dots (Omarchy-like)
///   tiles                focused workspace as a solid tile, others as plain numbers
/// A workspace shown on another display gets an outline instead of a fill.
enum WorkspaceIcon {
    enum Style { case focused, visible, occupied }
    enum Look: String { case number, segmented, dots, tiles }

    struct Slot: CustomStringConvertible {
        let label: String
        let style: Style
        var description: String { "\(label):\(style)" }
    }

    static let height: CGFloat = 18

    /// Long names are shortened so the menu bar stays tidy.
    static func label(_ name: String) -> String { name.count > 10 ? String(name.prefix(9)) + "…" : name }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let desc = (base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor).addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: desc, size: size) ?? base
    }

    private static func textWidth(_ s: String, _ f: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }

    /// The current workspace only, as Apple's own "3.square.fill" symbol so it matches the system icons.
    /// Names and numbers past 50 get the same rounded square, drawn.
    private static func renderNumber(_ label: String, mode: String?, secureInput: Bool, warning: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let symbol = Int(label).flatMap { (0...50).contains($0) ? $0 : nil }.flatMap {
            NSImage(systemSymbolName: "\($0).square.fill", accessibilityDescription: "Workspace \($0)")?
                .withSymbolConfiguration(config)
        }
        if let symbol, mode == nil, !secureInput, !warning {
            symbol.isTemplate = true
            return symbol
        }
        let labelFont = font(11.5, .bold)
        let modeFont = font(9.5, .bold)
        let squareSize = symbol?.size ?? NSSize(width: max(17, textWidth(label, labelFont) + 10), height: 17)
        let h = max(height, squareSize.height)
        var x: CGFloat = 0
        var lockRect: NSRect?
        if secureInput || warning {
            lockRect = NSRect(x: 0, y: (h - 14) / 2, width: 14, height: 14)
            x += 19
        }
        var modeRect: NSRect?
        let modeText = mode?.uppercased()
        if let modeText {
            let w = textWidth(modeText, modeFont) + 14
            modeRect = NSRect(x: x, y: (h - 16) / 2, width: w, height: 16)
            x += w + 5
        }
        let badge = warning ? "exclamationmark.triangle.fill" : "lock.fill"
        let square = NSRect(x: x, y: (h - squareSize.height) / 2, width: squareSize.width, height: squareSize.height)
        let image = NSImage(size: NSSize(width: square.maxX, height: h), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.set()
            if let r = lockRect, let lock = NSImage(systemSymbolName: badge, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold)) {
                let s = lock.size
                lock.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
            }
            if let r = modeRect, let modeText {
                NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
                knockOut(modeText, modeFont, in: r, cg)
            }
            if let symbol {
                symbol.draw(in: square)
            } else {
                NSBezierPath(roundedRect: square, xRadius: 4.5, yRadius: 4.5).fill()
                knockOut(label, labelFont, in: square, cg)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func render(slots: [Slot], mode: String?, secureInput: Bool, warning: Bool = false, look: Look = .number) -> NSImage {
        if look == .number {
            return renderNumber(slots.first { $0.style == .focused }?.label ?? "", mode: mode, secureInput: secureInput,
                                warning: warning)
        }
        let h = height
        let numberFont = font(12, .semibold)
        let modeFont = font(9.5, .bold)

        // Leading accessories: Secure Input lock, binding mode pill.
        var x: CGFloat = 0
        var lockRect: NSRect?
        if secureInput {
            lockRect = NSRect(x: x, y: 2, width: 12, height: 14)
            x += 12 + 5
        }
        var modeRect: NSRect?
        let modeText = mode?.uppercased()
        if let modeText {
            let w = textWidth(modeText, modeFont) + 14
            modeRect = NSRect(x: x, y: 1, width: w, height: h - 2)
            x += w + 5
        }

        // Workspace segments.
        var rects: [NSRect] = []
        switch look {
        case .number: break  // handled by renderNumber
        case .segmented:
            for s in slots {
                let w = max(22, textWidth(s.label, numberFont) + 14)
                rects.append(NSRect(x: x, y: 0, width: w, height: h))
                x += w
            }
        case .dots:
            for s in slots {
                let w = s.style == .focused ? max(24, textWidth(s.label, numberFont) + 14) : 10
                rects.append(NSRect(x: x, y: 0, width: w, height: h))
                x += w + 3
            }
            if !slots.isEmpty { x -= 3 }
        case .tiles:
            for s in slots {
                let w = max(18, textWidth(s.label, numberFont) + 10)
                rects.append(NSRect(x: x, y: 1, width: w, height: h - 2))
                x += w + 3
            }
            if !slots.isEmpty { x -= 3 }
        }
        let total = max(1, slots.isEmpty ? x - 5 : x)

        let image = NSImage(size: NSSize(width: total, height: h), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            func fill(_ path: NSBezierPath, _ alpha: CGFloat) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                path.fill()
            }
            func capsule(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2) }

            if let r = lockRect, let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input")?
                .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold)) {
                let s = lock.size
                lock.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
            }
            if let r = modeRect, let modeText {
                fill(capsule(r), 1)
                knockOut(modeText, modeFont, in: r, cg)
            }

            switch look {
            case .number: break
            case .segmented:
                if let first = rects.first, let last = rects.last {
                    fill(capsule(NSRect(x: first.minX, y: 0, width: last.maxX - first.minX, height: h)), 0.13)
                }
                for (s, r) in zip(slots, rects) {
                    let thumb = capsule(r.insetBy(dx: 2, dy: 2))
                    switch s.style {
                    case .focused:
                        fill(thumb, 1)
                        knockOut(s.label, numberFont, in: r, cg)
                    case .visible:
                        let ring = capsule(r.insetBy(dx: 2.6, dy: 2.6))
                        ring.lineWidth = 1.2
                        NSColor.black.setStroke()
                        ring.stroke()
                        draw(s.label, numberFont, in: r, alpha: 1)
                    case .occupied:
                        draw(s.label, numberFont, in: r, alpha: 0.8)
                    }
                }
            case .dots:
                for (s, r) in zip(slots, rects) {
                    switch s.style {
                    case .focused:
                        fill(capsule(r.insetBy(dx: 0, dy: 1.5)), 1)
                        knockOut(s.label, numberFont, in: r, cg)
                    case .visible:
                        let ring = NSBezierPath(ovalIn: NSRect(x: r.midX - 3.5, y: r.midY - 3.5, width: 7, height: 7))
                        ring.lineWidth = 1.3
                        NSColor.black.setStroke()
                        ring.stroke()
                    case .occupied:
                        fill(NSBezierPath(ovalIn: NSRect(x: r.midX - 3, y: r.midY - 3, width: 6, height: 6)), 0.55)
                    }
                }
            case .tiles:
                for (s, r) in zip(slots, rects) {
                    let tile = NSBezierPath(roundedRect: r, xRadius: 4.5, yRadius: 4.5)
                    switch s.style {
                    case .focused:
                        fill(tile, 1)
                        knockOut(s.label, numberFont, in: r, cg)
                    case .visible:
                        let ring = NSBezierPath(roundedRect: r.insetBy(dx: 0.6, dy: 0.6), xRadius: 3.9, yRadius: 3.9)
                        ring.lineWidth = 1.2
                        NSColor.black.setStroke()
                        ring.stroke()
                        draw(s.label, numberFont, in: r, alpha: 1)
                    case .occupied:
                        draw(s.label, numberFont, in: r, alpha: 0.55)
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Centers digits on their cap height, which reads as optically centered in a small shape.
    private static func origin(_ s: String, _ f: NSFont, in r: NSRect) -> NSPoint {
        let w = (s as NSString).size(withAttributes: [.font: f]).width
        return NSPoint(x: r.midX - w / 2, y: (r.midY - f.capHeight / 2 + f.descender).rounded())
    }

    private static func draw(_ s: String, _ f: NSFont, in r: NSRect, alpha: CGFloat) {
        (s as NSString).draw(at: origin(s, f, in: r),
                             withAttributes: [.font: f, .foregroundColor: NSColor.black.withAlphaComponent(alpha)])
    }

    private static func knockOut(_ s: String, _ f: NSFont, in r: NSRect, _ cg: CGContext) {
        cg.saveGState()
        cg.setBlendMode(.destinationOut)
        (s as NSString).draw(at: origin(s, f, in: r), withAttributes: [.font: f, .foregroundColor: NSColor.black])
        cg.restoreGState()
    }
}
