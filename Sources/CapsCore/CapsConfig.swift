import Foundation
import PanespaceCore

/// What Caps+key does.
public enum CapsAction: Equatable, CustomStringConvertible {
    /// Send another keystroke (Caps+J → ↓, Caps+N → ⌘T).
    case key(KeyCombo)
    /// Open or focus an app; hides it when it's already in front.
    case open(String)
    /// Run a shell command.
    case exec(String)
    case url(String)
    /// Type text.
    case text(String)
    /// Run a panespace command.
    case panespace(String)
    /// Run an Apple Shortcut by name.
    case shortcut(String)
    /// A built-in: media keys, screenshot, lock, dark mode, …
    case special(Special)
    /// Swallow the key.
    case nothing

    public var description: String {
        switch self {
        case .key(let k): return "key \(k)"
        case .open(let a): return "open \(a)"
        case .exec(let c): return "exec \(c)"
        case .url(let u): return "url \(u)"
        case .text(let t): return "text \"\(t)\""
        case .panespace(let c): return "panespace \(c)"
        case .shortcut(let n): return "shortcut \(n)"
        case .special(let s): return "do \(s.rawValue)"
        case .nothing: return "nothing"
        }
    }
}

/// `~/.config/caps/config`:
///
///     tap escape                    # Caps alone → Escape (or: tap none / tap <action>)
///     bind t open Ghostty           # everywhere
///     app "Safari|Zen" {            # regex on the app name or bundle ID
///         bind n key cmd+t
///     }
///
/// Combos name the key plus any extra modifiers ("j", "shift+j"); Caps itself is implied.
/// Keys without a binding pass on to panespace, which sees them as Caps+key.
public struct CapsConfig {
    public struct AppLayer {
        public let pattern: String
        let regex: NSRegularExpression
        public var bindings: [KeyCombo: CapsAction] = [:]
        /// A binding's trailing comment, shown as its label on the cheat sheet.
        public var notes: [KeyCombo: String] = [:]

        func matches(app: String, bundleID: String) -> Bool {
            [app, bundleID].contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
    }

    public var global: [KeyCombo: CapsAction] = [:]
    public var globalNotes: [KeyCombo: String] = [:]
    public var apps: [AppLayer] = []
    /// Tapping Caps alone. Off by default: an unexpected Escape triggers shell plugins (e.g. thefuck on Esc Esc).
    public var tap: CapsAction?
    /// Holding Caps on its own for `holdDelay` seconds.
    public var hold: HoldMode = .cheatsheet
    public var holdDelay: Double = 0.45
    public var warnings: [String] = []

    public init() {}

    /// The action for Caps+`combo` in this app: app layers first (in file order), then global.
    /// nil = not Caps's key; pass it on.
    public func action(for combo: KeyCombo, app: String, bundleID: String) -> CapsAction? {
        for layer in apps where layer.matches(app: app, bundleID: bundleID) {
            if let a = layer.bindings[combo] { return a }
        }
        return global[combo]
    }

    public typealias Entry = (combo: KeyCombo, action: CapsAction, note: String?)

    /// Everything Caps does in this app, app-specific first (for the menu and cheat sheet).
    public func bindings(app: String, bundleID: String) -> (app: [Entry], global: [Entry]) {
        var specific: [KeyCombo: Entry] = [:]
        for layer in apps.reversed() where layer.matches(app: app, bundleID: bundleID) {
            for (k, a) in layer.bindings { specific[k] = (k, a, layer.notes[k]) }
        }
        let order = { (a: Entry, b: Entry) in a.combo.description < b.combo.description }
        return (specific.values.sorted(by: order),
                global.filter { specific[$0.key] == nil }.map { ($0.key, $0.value, globalNotes[$0.key]) }.sorted(by: order))
    }

    public static func parse(_ text: String) -> CapsConfig {
        var c = CapsConfig()
        var layer: AppLayer?
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            var line = Config.stripTrailingComment(trimmed).trimmingCharacters(in: .whitespaces)
            var bindKey: String?
            var note: String?
            if trimmed.lowercased().hasPrefix("bind ") {
                // The key itself may be ' or ` or ; — read it raw so it can't open a quote or a comment.
                let afterBind = trimmed.dropFirst(5).drop { $0.isWhitespace }
                let key = String(afterBind.prefix { !$0.isWhitespace })
                bindKey = key
                let rest = String(afterBind.dropFirst(key.count))
                let code = Config.stripTrailingComment(rest)
                line = "bind " + key + " " + code.trimmingCharacters(in: .whitespaces)
                let comment = rest.dropFirst(code.count).drop { $0 == "#" || $0.isWhitespace }.trimmingCharacters(in: .whitespaces)
                if let first = comment.first { note = first.uppercased() + comment.dropFirst() }
            }
            func warn(_ s: String) { c.warnings.append("line \(n + 1): \(s)") }
            if line == "}" {
                if let l = layer { c.apps.append(l) } else { warn("unexpected '}'") }
                layer = nil
                continue
            }
            let head = CommandParser.words(line).first?.lowercased() ?? ""
            let rest = CommandParser.rest(line)
            switch head {
            case "app":
                guard layer == nil else { warn("app blocks can't nest"); continue }
                guard line.hasSuffix("{"), let pattern = CommandParser.words(String(rest.dropLast())).first else {
                    warn("expected: app \"Name|Other\" {")
                    continue
                }
                do {
                    layer = AppLayer(pattern: pattern, regex: try NSRegularExpression(pattern: pattern, options: .caseInsensitive))
                } catch {
                    warn("bad app pattern '\(pattern)'")
                }
            case "bind":
                let spec = bindKey ?? ""
                guard var combo = KeyCombo.parse(spec) else { warn("unknown key '\(spec)'"); continue }
                combo.modifiers.remove(.caps)  // Caps is implied
                do {
                    let a = try action(String(line.dropFirst(5 + spec.count)).trimmingCharacters(in: .whitespaces))
                    if layer != nil {
                        layer!.bindings[combo] = a
                        layer!.notes[combo] = note
                    } else {
                        c.global[combo] = a
                        c.globalNotes[combo] = note
                    }
                } catch {
                    warn("\(spec): \(error)")
                }
            case "hold":
                switch rest.lowercased() {
                case "cheatsheet", "cheat-sheet", "help": c.hold = .cheatsheet
                case "blur": c.hold = .blur
                case "none", "nothing", "off": c.hold = .none
                default:
                    do { c.hold = .action(try action(rest)) } catch { warn("hold: \(error)") }
                }
            case "hold_delay":
                if let v = Double(rest), (0.1...3).contains(v) { c.holdDelay = v } else { warn("hold_delay takes seconds, 0.1–3") }
            case "tap":
                switch rest.lowercased() {
                case "none", "nothing", "off": c.tap = nil
                case "escape", "esc": c.tap = .key(KeyCombo(keyCode: 0x35, modifiers: []))
                default:
                    do { c.tap = try action(rest) } catch { warn("tap: \(error)") }
                }
            default:
                warn("unknown directive '\(head)'")
            }
        }
        if let l = layer { c.warnings.append("unclosed app block '\(l.pattern)'") }
        return c
    }

    static func action(_ s: String) throws -> CapsAction {
        let verb = CommandParser.words(s).first?.lowercased() ?? ""
        let arg = CommandParser.rest(s)
        func need() throws -> String {
            guard !arg.isEmpty else { throw ParseError("'\(verb)' needs an argument") }
            return arg
        }
        switch verb {
        case "key":
            guard let k = KeyCombo.parse(try need()) else { throw ParseError("unknown key '\(arg)'") }
            return .key(k)
        case "open": return .open(unquote(try need()))
        case "exec": return .exec(try need())
        case "url": return .url(unquote(try need()))
        case "text": return .text(unquote(try need()).replacingOccurrences(of: "\\n", with: "\n"))
        case "panespace": return .panespace(try need())
        case "shortcut": return .shortcut(unquote(try need()))
        case "do":
            guard let s = Special(rawValue: try need().lowercased()) else {
                throw ParseError("unknown 'do \(arg)'; one of: " + Special.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return .special(s)
        case "nothing", "none": return .nothing
        case "": throw ParseError("missing action")
        default: throw ParseError("unknown action '\(verb)' (key, open, exec, url, text, panespace, shortcut, do, nothing)")
        }
    }

    static func unquote(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, f == "\"" || f == "'", s.last == f else { return s }
        return String(s.dropFirst().dropLast())
    }
}

public enum HoldMode: Equatable {
    /// Blur the screen and show what Caps+key does here.
    case cheatsheet
    /// Just blur the screen (a privacy curtain while you hold Caps).
    case blur
    case none
    case action(CapsAction)
}

/// Built-in actions: `bind <key> do <name>`.
public enum Special: String, CaseIterable {
    case playPause = "play-pause", nextTrack = "next-track", previousTrack = "previous-track"
    case volumeUp = "volume-up", volumeDown = "volume-down", mute
    case brightnessUp = "brightness-up", brightnessDown = "brightness-down"
    case keyboardLightUp = "keyboard-light-up", keyboardLightDown = "keyboard-light-down"
    case screenshot, screenshotFile = "screenshot-file", screenshotUI = "screenshot-ui"
    case lock, sleepDisplay = "sleep-display", sleep
    case darkMode = "dark-mode"
    case showDesktop = "show-desktop", missionControl = "mission-control", appWindows = "app-windows"
    case spotlight, emoji
    case keepAwake = "keep-awake"
    case pastePlain = "paste-plain"
    case quitApp = "quit-app", forceQuitApp = "force-quit-app", hideApp = "hide-app", hideOthers = "hide-others"
    case cheatsheet
    case editConfig = "edit-config", reloadConfig = "reload-config"

    public var label: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brighter"
        case .brightnessDown: return "Dimmer"
        case .keyboardLightUp: return "Keyboard light up"
        case .keyboardLightDown: return "Keyboard light down"
        case .screenshot: return "Screenshot to clipboard"
        case .screenshotFile: return "Screenshot to file"
        case .screenshotUI: return "Screenshot & record"
        case .lock: return "Lock screen"
        case .sleepDisplay: return "Sleep display"
        case .sleep: return "Sleep Mac"
        case .darkMode: return "Dark mode"
        case .showDesktop: return "Show desktop"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App windows"
        case .spotlight: return "Spotlight"
        case .emoji: return "Emoji"
        case .keepAwake: return "Keep Mac awake"
        case .pastePlain: return "Paste as plain text"
        case .quitApp: return "Quit app"
        case .forceQuitApp: return "Force quit app"
        case .hideApp: return "Hide app"
        case .hideOthers: return "Hide other apps"
        case .cheatsheet: return "Show this sheet"
        case .editConfig: return "Edit Caps config"
        case .reloadConfig: return "Reload Caps config"
        }
    }
}

public enum DefaultCapsConfig {
    public static let text = #"""
# ═══════════════════════════════════════════════════════════════════════════════
#  Caps — your Caps Lock key, programmable                    ~/.config/caps/config
#  Saved changes apply instantly · check for mistakes with:   caps check-config
# ═══════════════════════════════════════════════════════════════════════════════
#
#  HOW IT WORKS
#    Hold Caps Lock and press a key: Caps runs what you bound to that key.
#    Hold Caps on its own: the screen blurs and shows every Caps key for the app
#    you're in (release to close).
#    Bindings in an  app "…" { }  block only work in those apps and beat global ones.
#    Keys you don't bind here go to panespace (Caps+H focus, Caps+1 workspace, …),
#    so binding one of panespace's keys here takes it over.
#
#  KEYS
#    a–z  0–9  f1–f20  return space tab escape backspace delete
#    left right up down home end pageup pagedown   [ ] ; ' , . / \ ` - =
#    Add modifiers with +   shift+j · ctrl+a · cmd+shift+t     (Caps is implied)
#
#  ACTIONS
#    key <combo>          press another key            key cmd+w · key down · key ctrl+a
#    open <app>           open/focus an app; again → hide it        open Safari
#    url <link>           open a link                  url https://github.com
#    exec <command>       run a shell command          exec say "hello"
#    text "<text>"        type text  ("\n" = Return)   text "Thanks,\nNischal"
#    shortcut "<name>"    run an Apple Shortcut        shortcut "Turn On Do Not Disturb"
#    panespace <command>     run a panespace command         panespace workspace 3
#    do <built-in>        one of the built-ins below   do screenshot
#    nothing              swallow the key
#
#  BUILT-INS  (do …)
#    Media      play-pause · next-track · previous-track · volume-up · volume-down · mute
#    Display    brightness-up · brightness-down · dark-mode · sleep-display
#    Keyboard   keyboard-light-up · keyboard-light-down
#    Capture    screenshot (area → clipboard) · screenshot-file (area → Desktop)
#               screenshot-ui (the full screenshot & screen-recording toolbar)
#    System     lock · sleep · keep-awake (toggle: no sleep until pressed again)
#               spotlight · emoji
#    Spaces     show-desktop · mission-control · app-windows
#    Apps       quit-app · force-quit-app · hide-app · hide-others
#    Text       paste-plain (paste without formatting)
#    Caps       cheatsheet · edit-config · reload-config
#
#  panespace already uses these with Caps:
#    H J K L ←↓↑→  (focus; +Shift = move)   1–0 (workspaces; +Shift = send window)
#    A  B  V  E  F  R  S  W  Space  Tab  [  ]  -  Return  and a few Shift combos
# ═══════════════════════════════════════════════════════════════════════════════


# ── Caps on its own ────────────────────────────────────────────────────────────
tap none              # quick tap does nothing.  tap escape · tap <any action>
                      #   (careful: Escape-on-tap can trigger shell plugins like thefuck)
hold cheatsheet       # hold: blur the screen + show every Caps key for this app
                      #   hold blur (just a privacy blur) · hold none · hold <any action>
hold_delay 0.45       # seconds of holding before the sheet appears


# ── Everywhere ─────────────────────────────────────────────────────────────────
bind p        do play-pause
bind m        do mute
bind ;        do volume-down
bind '        do volume-up
bind c        do screenshot          # drag an area; it lands on the clipboard
bind d        do show-desktop
bind o        do mission-control
bind i        do dark-mode           # asks once for permission to change appearance
bind shift+v  do paste-plain
bind /        do cheatsheet          # same sheet as holding Caps

# More ideas (remove the # to turn one on):
# bind escape   do lock
# bind `        do keep-awake
# bind g        url https://github.com
# bind shift+d  exec open ~/Downloads
# bind shift+e  text "you@example.com"
# bind shift+n  shortcut "Turn On Do Not Disturb"


# ── Open apps (press again to hide) ────────────────────────────────────────────
# bind t  open Terminal
# bind z  open Safari
# bind n  open Notes


# ── Per-app keys (an app block only works in those apps) ───────────────────────
# Browsers
# app "Safari|Chrome|Firefox|Zen|Arc|Brave" {
#     bind x  key cmd+w           # close tab
#     bind y  key cmd+shift+t     # reopen closed tab
#     bind u  key cmd+l           # address bar
#     bind ,  key cmd+shift+[     # previous tab
#     bind .  key cmd+shift+]     # next tab
# }

# Terminals
# app "Terminal|iTerm|Ghostty|kitty|Alacritty|WezTerm" {
#     bind u  key ctrl+u          # clear the line
#     bind x  key ctrl+c          # interrupt
# }

# Finder
# app "Finder" {
#     bind .  key cmd+shift+.     # show/hide hidden files
#     bind g  key cmd+shift+g     # go to folder
#     bind u  key cmd+up          # parent folder
# }

# Code editors
# app "Code|Cursor|Zed|Xcode" {
#     bind ,  key cmd+shift+p     # command palette
#     bind x  key cmd+shift+k     # delete line
# }
"""#
}
