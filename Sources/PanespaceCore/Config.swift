import CoreGraphics
import Foundation

public enum DefaultOrientation: Equatable { case auto, horizontal, vertical }

public struct Rule {
    public var criteria: Criteria
    public var command: String
}

public struct Assignment {
    public var criteria: Criteria
    public var workspace: WorkspaceTarget
}

/// i3-compatible config. Unknown i3 directives (bar, font, client.*, …) are ignored so
/// an existing i3 config mostly just works.
public struct Config {
    public var modes: [String: [KeyCombo: String]] = ["default": [:]]
    public var gaps = Gaps()
    public var smartGaps = false
    public var defaultOrientation = DefaultOrientation.auto
    public var workspaceLayout: Layout?
    public var autoBackAndForth = false
    public var focusFollowsMouse = false
    public var mouseWarping = true
    public var focusWrapping = true
    public var accordionPadding: CGFloat = 30
    public var floatingModifier: Modifiers?
    /// ⌃⌘F / Globe+F and the green button use panespace fullscreen instead of a macOS full-screen Space
    /// (windows on other Spaces can't be tiled). `native_fullscreen macos` turns this off.
    public var interceptNativeFullscreen = true
    /// Switching workspaces shows the new windows before parking the old ones, so the bare desktop never flashes.
    public var smoothLayout = true
    /// Menu bar indicator look: segmented | dots | tiles.
    public var workspaceIndicator = "number"
    /// nil = leave the macOS menu bar/Dock alone; true/false = set immersive mode at startup.
    public var immersive: Bool?
    /// Focus border drawn around the focused window (i3: default_border pixel N / client.focused).
    public var borderWidth: CGFloat = 0
    public var borderColor = "#5294E2"
    public var borderRadius: CGFloat = 12
    public var execs: [String] = []
    public var execAlways: [String] = []
    public var rules: [Rule] = []
    public var assignments: [Assignment] = []
    public var workspaceOutputs: [String: [String]] = [:]
    public var warnings: [String] = []

    public init() {}

    /// Any binding or the floating modifier uses Caps Lock.
    public var usesCapsLock: Bool {
        floatingModifier?.contains(.caps) == true || modes.values.contains { $0.keys.contains { $0.modifiers.contains(.caps) } }
    }

    static let ignored: Set<String> = [
        "font", "hide_edge_borders", "new_window", "new_float",
        "title_align", "floating_minimum_size", "floating_maximum_size", "popup_during_fullscreen",
        "force_display_urgency_hint", "focus_on_window_activation", "show_marks", "ipc-socket", "ipc_socket",
        "force_focus_wrapping", "for_window_title", "include", "smart_borders", "border_radius", "bindswitch",
        "no_focus", "tiling_drag", "bar", "default_floating_border",
    ]

    /// Drops a trailing "  # comment" (a `#` after whitespace and followed by a space), outside quotes.
    /// Colors like `#5294e2` and quoted text are left alone.
    public static func stripTrailingComment(_ line: String) -> String {
        let chars = Array(line)
        var quote: Character?
        for i in chars.indices {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#", i > 0, chars[i - 1].isWhitespace, i + 1 == chars.count || chars[i + 1] == " " {
                return String(chars[..<i])
            }
        }
        return line
    }

    public static func parse(_ text: String) -> Config {
        var c = Config()
        var vars: [(String, String)] = []
        var modeStack: [String] = []
        var skipDepth = 0

        // Join continuation lines.
        var lines: [(Int, String)] = []
        var pending = ""
        var pendingLine = 0
        for (n, l) in text.components(separatedBy: .newlines).enumerated() {
            if pending.isEmpty { pendingLine = n + 1 }
            if l.hasSuffix("\\") { pending += l.dropLast() + " "; continue }
            lines.append((pendingLine, pending + l))
            pending = ""
        }

        for (lineNo, rawLine) in lines {
            var line = Config.stripTrailingComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            func warn(_ s: String) { c.warnings.append("line \(lineNo): \(s)") }

            if skipDepth > 0 {
                if line.hasSuffix("{") { skipDepth += 1 }
                if line == "}" { skipDepth -= 1 }
                continue
            }
            if line == "}" {
                if modeStack.popLast() == nil { warn("unexpected '}'") }
                continue
            }

            let first = CommandParser.words(line).first?.lowercased() ?? ""
            if first == "set" {
                let w = CommandParser.words(line)
                guard w.count >= 3, w[1].hasPrefix("$") else { warn("bad set"); continue }
                var value = CommandParser.rest(CommandParser.rest(line))
                for (k, v) in vars { value = value.replacingOccurrences(of: k, with: v) }
                vars.removeAll { $0.0 == w[1] }
                vars.append((w[1], value))
                vars.sort { $0.0.count > $1.0.count }
                continue
            }
            for (k, v) in vars { line = line.replacingOccurrences(of: k, with: v) }
            let w = CommandParser.words(line)
            let args = Array(w.dropFirst())
            let a = args.map { $0.lowercased() }
            func bool(_ s: String?) -> Bool { ["yes", "on", "true", "1", "enable", "output"].contains(s ?? "") }

            switch first {
            case "bindsym", "bindcode":
                var rest = CommandParser.rest(line)
                var release = false
                while rest.hasPrefix("--") {
                    if rest.hasPrefix("--release") { release = true }
                    rest = CommandParser.rest(rest)
                }
                let keySpec = CommandParser.words(rest).first ?? ""
                let command = CommandParser.rest(rest)
                guard let combo = KeyCombo.parse(keySpec, isCode: first == "bindcode") else {
                    warn("unknown key '\(keySpec)'"); continue
                }
                guard !command.isEmpty else { warn("binding '\(keySpec)' has no command"); continue }
                if release { warn("--release is not supported; binding fires on press") }
                do { _ = try CommandParser.parse(command) } catch { warn("\(keySpec): \(error)") }
                let mode = modeStack.last ?? "default"
                c.modes[mode, default: [:]][combo] = command

            case "mode":
                guard line.hasSuffix("{"), let name = args.first(where: { !$0.hasPrefix("--") }) else {
                    warn("expected: mode \"name\" {"); continue
                }
                modeStack.append(name)
                c.modes[name, default: [:]] = c.modes[name] ?? [:]

            case "gaps":
                guard a.count >= 2, let v = Double(a[1].replacingOccurrences(of: "px", with: "")) else {
                    warn("expected: gaps inner|outer|horizontal|vertical|top|bottom|left|right <px>"); continue
                }
                let px = CGFloat(v)
                switch a[0] {
                case "inner": c.gaps.inner = px
                case "outer": (c.gaps.top, c.gaps.bottom, c.gaps.left, c.gaps.right) = (px, px, px, px)
                case "horizontal": (c.gaps.left, c.gaps.right) = (px, px)
                case "vertical": (c.gaps.top, c.gaps.bottom) = (px, px)
                case "top": c.gaps.top = px
                case "bottom": c.gaps.bottom = px
                case "left": c.gaps.left = px
                case "right": c.gaps.right = px
                default: warn("unknown gaps kind '\(a[0])'")
                }

            case "default_border", "new_window":
                switch a.first {
                case "none": c.borderWidth = 0
                case "pixel", "normal": c.borderWidth = a.count > 1 ? CGFloat(Double(a[1]) ?? 2) : 2
                default: warn("expected: default_border none|pixel <px>")
                }
            case "border_radius":
                if let v = a.first.flatMap(Double.init) { c.borderRadius = CGFloat(v) } else { warn("bad border_radius") }
            case "client.focused":
                // i3: border background text indicator [child_border]; the child border is what frames the window.
                let colors = args.filter { $0.hasPrefix("#") }
                if let col = colors.count >= 5 ? colors[4] : colors.first { c.borderColor = col } else { warn("client.focused needs colors") }
            case "immersive": c.immersive = bool(a.first)
            case "native_fullscreen": c.interceptNativeFullscreen = a.first != "macos"
            case "smooth_layout": c.smoothLayout = bool(a.first)
            case "workspace_indicator":
                if let v = a.first, ["number", "segmented", "dots", "tiles"].contains(v) { c.workspaceIndicator = v } else {
                    warn("expected: workspace_indicator number|segmented|dots|tiles")
                }
            case "smart_gaps": c.smartGaps = bool(a.first)
            case "workspace_auto_back_and_forth": c.autoBackAndForth = bool(a.first)
            case "focus_follows_mouse": c.focusFollowsMouse = bool(a.first)
            case "mouse_warping": c.mouseWarping = a.first != "none"
            case "focus_wrapping": c.focusWrapping = a.first != "no" && a.first != "false"
            case "accordion_padding":
                if let v = a.first.flatMap(Double.init) { c.accordionPadding = CGFloat(v) } else { warn("bad accordion_padding") }
            case "default_orientation":
                switch a.first {
                case "horizontal": c.defaultOrientation = .horizontal
                case "vertical": c.defaultOrientation = .vertical
                default: c.defaultOrientation = .auto
                }
            case "workspace_layout":
                switch a.first {
                case "tabbed": c.workspaceLayout = .tabbed
                case "stacking", "stacked": c.workspaceLayout = .stacking
                default: c.workspaceLayout = nil
                }
            case "floating_modifier":
                var m: Modifiers = []
                for p in (args.first ?? "").split(separator: "+") {
                    if let x = Modifiers.named(String(p)) { m.formUnion(x) } else { warn("unknown modifier '\(p)'") }
                }
                c.floatingModifier = m.isEmpty ? nil : m

            case "exec", "exec_always":
                var cmd = CommandParser.rest(line)
                if cmd.hasPrefix("--no-startup-id") { cmd = CommandParser.rest(cmd) }
                if first == "exec" { c.execs.append(cmd) } else { c.execAlways.append(cmd) }

            case "for_window", "assign":
                let body = CommandParser.rest(line)
                guard body.hasPrefix("["), let close = CommandParser.closingBracket(body) else {
                    warn("\(first) needs [criteria]"); continue
                }
                let crit: Criteria
                do { crit = try Criteria.parse(String(body[body.index(after: body.startIndex)..<close])) } catch {
                    warn("\(error)"); continue
                }
                let tail = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                if first == "for_window" {
                    do { _ = try CommandParser.parse(tail) } catch { warn("for_window: \(error)"); continue }
                    c.rules.append(Rule(criteria: crit, command: tail))
                } else {
                    var t = CommandParser.words(tail)
                    if let f = t.first, f == "→" || f == "->" { t.removeFirst() }
                    if t.first?.lowercased() == "workspace" { t.removeFirst() }
                    if t.first?.lowercased() == "output" { warn("assign to output is not supported"); continue }
                    let isNumber = t.first?.lowercased() == "number"
                    if isNumber { t.removeFirst() }
                    let name = t.joined(separator: " ")
                    guard !name.isEmpty else { warn("assign needs a workspace"); continue }
                    c.assignments.append(Assignment(criteria: crit, workspace: isNumber ? .number(name) : .name(name)))
                }

            case "workspace":
                // workspace <name> output <out1> [<out2> …]
                guard let o = a.firstIndex(of: "output"), o > 0, o + 1 < args.count else {
                    warn("expected: workspace <name> output <output>"); continue
                }
                c.workspaceOutputs[args[..<o].joined(separator: " ")] = Array(args[(o + 1)...])

            default:
                if first.hasPrefix("client.") || Config.ignored.contains(first) {
                    if line.hasSuffix("{") { skipDepth = 1 }
                } else if line.hasSuffix("{") {
                    skipDepth = 1
                    warn("ignoring unknown block '\(first)'")
                } else {
                    warn("unknown directive '\(first)'")
                }
            }
        }
        if !modeStack.isEmpty { c.warnings.append("unclosed mode block '\(modeStack.last!)'") }
        return c
    }
}
