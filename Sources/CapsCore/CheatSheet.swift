import Foundation
import ZSpaceCore

public struct CheatRow: Equatable {
    public let keys: String
    public let label: String
}

public struct CheatSection: Equatable {
    public let title: String
    public let rows: [CheatRow]
    public init(title: String, rows: [CheatRow]) {
        self.title = title
        self.rows = rows
    }
}

/// What the hold-Caps sheet shows: Caps's bindings for the frontmost app, then everywhere, then the
/// zspace bindings Caps passes through — with friendly labels and repetitive keys collapsed
/// (1…0 → one row, H and ← → one row).
public enum CheatSheet {
    public static func sections(config: CapsConfig, app: String, bundleID: String,
                                zspace: [(KeyCombo, String)]) -> [CheatSection] {
        let caps = config.bindings(app: app, bundleID: bundleID)
        var out: [CheatSection] = []
        func add(_ title: String, _ rows: [CheatRow]) { if !rows.isEmpty { out.append(CheatSection(title: title, rows: rows)) } }
        add("In \(app)", caps.app.map { CheatRow(keys: keys($0.combo), label: $0.note ?? label($0.action)) })
        add("Everywhere", caps.global.map { CheatRow(keys: keys($0.combo), label: $0.note ?? label($0.action)) })

        // zspace sees Caps+key only for keys Caps doesn't take in this app.
        let taken = Set(caps.app.map(\.combo) + caps.global.map(\.combo))
        var wm: [(KeyCombo, String)] = []
        for (combo, cmd) in zspace where combo.modifiers.contains(.caps) {
            var k = combo
            k.modifiers.remove(.caps)
            if !taken.contains(k) { wm.append((k, cmd)) }
        }
        let isWorkspace = { (c: String) in c.hasPrefix("workspace") || c.hasPrefix("move container to workspace") || c.hasPrefix("move workspace") }
        add("Windows", zspaceRows(wm.filter { !isWorkspace($0.1) }))
        add("Workspaces", zspaceRows(wm.filter { isWorkspace($0.1) }))
        return out
    }

    /// Groups zspace bindings: numbered workspaces into one row each, duplicate commands into "H  ←".
    static func zspaceRows(_ bindings: [(KeyCombo, String)]) -> [CheatRow] {
        var rows: [(order: Int, row: CheatRow)] = []
        var byCommand: [String: [KeyCombo]] = [:]
        var numbered: [String: [(Int, KeyCombo)]] = [:]  // command template → (n, key)
        for (k, cmd) in bindings {
            if let (template, n) = numberedCommand(cmd) {
                numbered[template, default: []].append((n, k))
            } else {
                byCommand[cmd, default: []].append(k)
            }
        }
        for (template, items) in numbered {
            let sorted = items.sorted { $0.0 < $1.0 }.map(\.1)
            let range = sorted.count > 1
                ? modSymbols(sorted[0]) + keyName(sorted[0]) + "…" + keyName(sorted[sorted.count - 1])
                : keys(sorted[0])
            let label = template.hasPrefix("move") ? "Send window to workspace" : "Go to workspace"
            rows.append((order(template), CheatRow(keys: range, label: label)))
        }
        for (cmd, combos) in byCommand {
            let ks = combos.sorted { (isArrow($0) ? 1 : 0, $0.description) < (isArrow($1) ? 1 : 0, $1.description) }
            rows.append((order(cmd), CheatRow(keys: ks.map(keys).joined(separator: " "), label: zspaceLabel(cmd))))
        }
        return rows.sorted { ($0.order, $0.row.label) < ($1.order, $1.row.label) }.map(\.row)
    }

    private static func numberedCommand(_ cmd: String) -> (String, Int)? {
        for prefix in ["workspace number ", "move container to workspace number ", "workspace ", "move container to workspace "] {
            if cmd.hasPrefix(prefix), let n = Int(cmd.dropFirst(prefix.count)) { return (prefix.trimmingCharacters(in: .whitespaces), n) }
        }
        return nil
    }

    private static func isArrow(_ k: KeyCombo) -> Bool { (0x7B...0x7E).contains(k.keyCode) }

    private static func order(_ cmd: String) -> Int {
        let verbs = ["focus", "move container to workspace", "workspace", "move workspace", "move", "split", "layout",
                     "fullscreen", "floating", "immersive", "mode", "resize", "balance", "scratchpad", "kill", "exec",
                     "reload", "exit"]
        return verbs.firstIndex { cmd.hasPrefix($0) } ?? verbs.count
    }

    // MARK: Labels

    public static func label(_ a: CapsAction) -> String {
        switch a {
        case .key(let k): return "Press " + keys(k)
        case .open(let app): return "Open \(app)"
        case .exec(let cmd):
            let first = cmd.split(separator: " ").first.map(String.init) ?? cmd
            return "Run " + (first as NSString).lastPathComponent
        case .url(let u): return URL(string: u)?.host ?? u
        case .text(let t): return "Type “" + (t.count > 18 ? t.prefix(17) + "…" : t) + "”"
        case .zspace(let c): return zspaceLabel(c)
        case .shortcut(let n): return "Shortcut “\(n)”"
        case .special(let s): return s.label
        case .nothing: return "Nothing"
        }
    }

    public static func zspaceLabel(_ c: String) -> String {
        let arrows = ["left": "←", "right": "→", "up": "↑", "down": "↓"]
        let w = CommandParser.words(c).map { $0.lowercased() }
        func arg(_ i: Int) -> String { i < w.count ? w[i] : "" }
        switch arg(0) {
        case "focus":
            if let a = arrows[arg(1)] { return "Focus \(a)" }
            return ["parent": "Focus parent", "child": "Focus child", "mode_toggle": "Tiled ↔ floating focus"][arg(1)] ?? c
        case "move":
            if let a = arrows[arg(1)] { return "Move window \(a)" }
            if arg(1) == "scratchpad" { return "Hide to scratchpad" }
            if arg(1) == "workspace" { return "Workspace to next screen" }
            return c
        case "split":
            return ["h": "Next window beside", "horizontal": "Next window beside", "v": "Next window below",
                    "vertical": "Next window below", "toggle": "Toggle split"][arg(1)] ?? c
        case "layout":
            if arg(1) == "toggle" { return "Flip split direction" }
            return ["tabbed": "Tabbed layout", "stacking": "Stacked layout", "stacked": "Stacked layout",
                    "splith": "Side by side", "splitv": "Stacked rows", "default": "Default layout"][arg(1)] ?? c
        case "fullscreen": return "Fullscreen"
        case "floating": return "Float window"
        case "immersive": return "Immersive mode"
        case "mode": return arg(1) == "default" ? "Leave mode" : "\(arg(1).capitalized) mode"
        case "balance": return "Equal sizes"
        case "scratchpad": return "Show scratchpad"
        case "kill": return "Close window"
        case "reload": return "Reload zspace"
        case "exit": return "Quit zspace"
        case "workspace":
            return ["back_and_forth": "Last workspace", "next": "Next workspace", "prev": "Previous workspace",
                    "next_on_output": "Next workspace", "prev_on_output": "Previous workspace"][arg(1)] ?? "Workspace \(arg(1))"
        case "exec":
            // "open -na Ghostty", "tell application \"Terminal\" …" → "Open Ghostty"
            for pattern in [#"open\s+-n?a\s+"?([^"]+?)"?(\s|$)"#, #"application \\?"([^"\\]+)"#] {
                if let r = try? NSRegularExpression(pattern: pattern),
                   let m = r.firstMatch(in: c, range: NSRange(c.startIndex..., in: c)), let g = Range(m.range(at: 1), in: c) {
                    return "Open " + c[g]
                }
            }
            return "Run command"
        default: return c
        }
    }

    // MARK: Keys

    /// "shift+cmd+t" → "⇧⌘T", arrows and punctuation as symbols.
    public static func keys(_ k: KeyCombo) -> String { modSymbols(k) + keyName(k) }

    static func modSymbols(_ k: KeyCombo) -> String {
        var s = ""
        if k.modifiers.contains(.control) { s += "⌃" }
        if k.modifiers.contains(.option) { s += "⌥" }
        if k.modifiers.contains(.shift) { s += "⇧" }
        if k.modifiers.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(_ k: KeyCombo) -> String {
        let symbols: [UInt16: String] = [
            0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓", 0x24: "↩", 0x31: "Space", 0x30: "⇥", 0x35: "Esc",
            0x33: "⌫", 0x75: "⌦", 0x73: "Home", 0x77: "End", 0x74: "PgUp", 0x79: "PgDn", 0x4C: "⌤",
        ]
        return symbols[k.keyCode] ?? (k.keyName ?? "?").uppercased()
    }
}
