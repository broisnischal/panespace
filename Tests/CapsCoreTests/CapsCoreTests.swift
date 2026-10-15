import XCTest
import ZSpaceCore
@testable import CapsCore

final class CapsConfigTests: XCTestCase {
    func k(_ s: String) -> KeyCombo { KeyCombo.parse(s)! }

    func testDefaultConfigParsesCleanly() {
        let c = CapsConfig.parse(DefaultCapsConfig.text)
        XCTAssertEqual(c.warnings, [])
        XCTAssertNil(c.tap)
        XCTAssertEqual(CapsConfig.parse("tap escape").tap, .key(k("escape")))
    }

    func testAppLayerBeatsGlobalAndFallsThrough() {
        let c = CapsConfig.parse("""
        bind t open Ghostty
        bind n open Notes
        app "Zen|Safari" {
            bind n key cmd+t     # new tab
            bind , key cmd+shift+[
        }
        app "com\\.apple\\.Terminal" {
            bind shift+j key down
        }
        """)
        XCTAssertEqual(c.warnings, [])
        XCTAssertEqual(c.action(for: k("n"), app: "Zen", bundleID: "app.zen-browser.zen"), .key(k("cmd+t")))
        XCTAssertEqual(c.action(for: k("n"), app: "Kero", bundleID: "sh.kero"), .open("Notes"))
        XCTAssertEqual(c.action(for: k("t"), app: "Zen", bundleID: ""), .open("Ghostty"))
        XCTAssertEqual(c.action(for: k("comma"), app: "safari", bundleID: ""), .key(k("cmd+shift+bracketleft")))
        XCTAssertEqual(c.action(for: k("shift+j"), app: "Terminal", bundleID: "com.apple.Terminal"), .key(k("down")))
        XCTAssertNil(c.action(for: k("j"), app: "Terminal", bundleID: "com.apple.Terminal"))  // → zspace
        XCTAssertNil(c.action(for: k("h"), app: "Zen", bundleID: ""))
        let b = c.bindings(app: "Zen", bundleID: "")
        XCTAssertEqual(b.app.count, 2)
        XCTAssertEqual(b.app.first { $0.combo == k("n") }?.note, "New tab")  // trailing comment → label
        XCTAssertEqual(b.global.map(\.action), [.open("Ghostty")])  // "n" is overridden here
    }

    func testActions() throws {
        XCTAssertEqual(try CapsConfig.action("text \"hi\\nthere\""), .text("hi\nthere"))
        XCTAssertEqual(try CapsConfig.action("open \"System Settings\""), .open("System Settings"))
        XCTAssertEqual(try CapsConfig.action("exec echo 'a b' | pbcopy"), .exec("echo 'a b' | pbcopy"))
        XCTAssertEqual(try CapsConfig.action("zspace workspace 3"), .zspace("workspace 3"))
        XCTAssertEqual(try CapsConfig.action("nothing"), .nothing)
        XCTAssertThrowsError(try CapsConfig.action("launch rockets"))
        XCTAssertThrowsError(try CapsConfig.action("key nope"))
    }

    func testSpecialsAndHold() {
        let c = CapsConfig.parse("bind m do mute\nbind s shortcut \"Focus Mode\"\nhold blur\nhold_delay 0.6")
        XCTAssertEqual(c.warnings, [])
        XCTAssertEqual(c.global[k("m")], .special(.mute))
        XCTAssertEqual(c.global[k("s")], .shortcut("Focus Mode"))
        XCTAssertEqual(c.hold, .blur)
        XCTAssertEqual(c.holdDelay, 0.6)
        XCTAssertEqual(CapsConfig.parse("hold do lock").hold, .action(.special(.lock)))
        XCTAssertEqual(CapsConfig().hold, .cheatsheet)
        XCTAssertEqual(CapsConfig.parse("bind m do teleport").warnings.count, 1)
    }

    func testCheatSheetGroupsZspaceBindings() {
        let z = Config.parse("set $mod caps\n" + DefaultConfig.text.replacingOccurrences(of: "set $mod ctrl+alt", with: ""))
        let zspace = z.modes["default"]!.map { ($0.key, $0.value) }
        let caps = CapsConfig.parse("bind z open Zen\napp \"Zen\" {\n bind h key cmd+[\n}")
        let s = CheatSheet.sections(config: caps, app: "Zen", bundleID: "", zspace: zspace)
        XCTAssertEqual(s.map(\.title), ["In Zen", "Everywhere", "Windows", "Workspaces"])
        XCTAssertEqual(s[0].rows, [CheatRow(keys: "H", label: "Press ⌘[")])
        XCTAssertEqual(s[1].rows, [CheatRow(keys: "Z", label: "Open Zen")])
        let windows = s[2].rows
        XCTAssertTrue(windows.contains(CheatRow(keys: "←", label: "Focus ←")))  // H is taken by Zen here
        XCTAssertTrue(windows.contains(CheatRow(keys: "J ↓", label: "Focus ↓")))
        XCTAssertTrue(windows.contains(CheatRow(keys: "⇧H ⇧←", label: "Move window ←")))
        XCTAssertTrue(windows.contains(CheatRow(keys: "↩", label: "Open Terminal")))
        let ws = s[3].rows
        XCTAssertTrue(ws.contains(CheatRow(keys: "1…0", label: "Go to workspace")))
        XCTAssertTrue(ws.contains(CheatRow(keys: "⇧1…0", label: "Send window to workspace")))
        XCTAssertTrue(ws.contains(CheatRow(keys: "⇥", label: "Last workspace")))
    }

    func testTapAndWarnings() {
        XCTAssertNil(CapsConfig.parse("tap none").tap)
        XCTAssertEqual(CapsConfig.parse("tap exec say hi").tap, .exec("say hi"))
        let bad = CapsConfig.parse("bind nope key a\nbind a frobnicate\nwat\napp \"x\" {\nbind a nothing")
        XCTAssertEqual(bad.warnings.count, 4)
        XCTAssertEqual(CapsConfig.parse("bind caps+a nothing").global[k("a")], .nothing)  // caps+ is implied
    }
}
