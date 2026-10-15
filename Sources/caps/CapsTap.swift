import AppKit
import CapsCore
import MacKit
import PanespaceCore

/// The keyboard hook. Sits at the head of the event chain (panespace sits at the tail), on its own thread.
///
/// While Caps (remapped to F18) is held:
/// - a key bound for the frontmost app, or globally, runs its action and never reaches anyone else;
/// - any other key is passed on tagged `CapsLock.heldTag`, so panespace treats it as Caps+key;
/// - mouse events are tagged too, so Caps+drag works in panespace.
/// Caps on its own (a quick tap) runs the `tap` action, Escape by default.
final class CapsTap {
    var onAction: (CapsAction) -> Void = { _ in }
    /// Main thread. Caps went down / was held alone for `holdDelay` / came up / another key was pressed.
    var onCapsDown: () -> Void = {}
    var onHold: () -> Void = {}
    var onCapsUp: () -> Void = {}
    var onKeyWhileHeld: () -> Void = {}

    private let lock = NSLock()
    private var config = CapsConfig()
    private var frontApp = (name: "", bundleID: "")
    private var held = false
    private var heldSince: UInt64 = 0
    private var usedWhileHeld = false
    private var holdGeneration = 0
    /// Physical key → the key we sent for it, so its key-up releases the right key.
    private var remapped: [UInt16: KeyCombo] = [:]
    private var tap: CFMachPort?
    private let source = CGEventSource(stateID: .privateState)
    private static let tapWindow: UInt64 = 300_000_000  // ns: a quick press-and-release counts as a tap

    func update(_ c: CapsConfig) { lock.withLock { config = c } }
    func setFrontApp(name: String, bundleID: String) { lock.withLock { frontApp = (name, bundleID) } }

    func start() -> Bool {
        var mask: CGEventMask = 0
        for t in [CGEventType.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                  .rightMouseDown, .rightMouseUp, .rightMouseDragged] { mask |= 1 << t.rawValue }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            Unmanaged<CapsTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passRetained(self).toOpaque()) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "caps.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if event.getIntegerValueField(.eventSourceUserData) == CapsLock.syntheticTag { return pass }  // ours

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.withLock { held = false }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .keyDown, .keyUp:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let down = type == .keyDown
            if code == CapsLock.f18KeyCode {
                capsKey(down: down, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                return nil  // the Caps key itself never reaches panespace or apps
            }
            if !down {
                if let k = lock.withLock({ remapped.removeValue(forKey: code) }) {
                    post(k, down: false)
                    return nil
                }
                if lock.withLock({ held }) { event.setIntegerValueField(.eventSourceUserData, value: CapsLock.heldTag) }
                return pass
            }
            let physicallyDown = CapsLock.isPhysicallyDown
            let lookup = lock.withLock { () -> (Bool, CapsAction?) in
                if held && !physicallyDown { held = false }  // missed the key-up: never leave Caps stuck
                guard held else { return (false, nil) }
                if !usedWhileHeld { DispatchQueue.main.async { self.onKeyWhileHeld() } }
                usedWhileHeld = true
                let combo = KeyCombo(keyCode: code, modifiers: CapsTap.modifiers(event.flags))
                return (true, config.action(for: combo, app: frontApp.name, bundleID: frontApp.bundleID))
            }
            guard lookup.0 else { return pass }
            guard let action = lookup.1 else {
                event.setIntegerValueField(.eventSourceUserData, value: CapsLock.heldTag)  // panespace's turn
                return pass
            }
            switch action {
            case .key(let k):
                lock.withLock { remapped[code] = k }
                post(k, down: true)  // key repeat re-posts it, so holding repeats
            case .nothing:
                break
            default:
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    DispatchQueue.main.async { self.onAction(action) }
                }
            }
            return nil

        default:  // mouse: let panespace see Caps+drag
            if lock.withLock({ held }) { event.setIntegerValueField(.eventSourceUserData, value: CapsLock.heldTag) }
            return pass
        }
    }

    private func capsKey(down: Bool, isRepeat: Bool) {
        let now = DispatchTime.now().uptimeNanoseconds
        let tapAction: CapsAction? = lock.withLock {
            if down {
                if !held {
                    (held, heldSince, usedWhileHeld) = (true, now, false)
                    holdGeneration += 1
                    let g = holdGeneration
                    DispatchQueue.main.async { self.onCapsDown() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + config.holdDelay) {
                        // Still held, alone, and the same press: it's a hold.
                        if self.lock.withLock({ self.held && !self.usedWhileHeld && self.holdGeneration == g }) { self.onHold() }
                    }
                }
                return nil
            }
            defer { held = false }
            DispatchQueue.main.async { self.onCapsUp() }
            return held && !usedWhileHeld && now - heldSince < CapsTap.tapWindow ? config.tap : nil
        }
        guard let tapAction, !isRepeat else { return }
        if case .key(let k) = tapAction {
            post(k, down: true)
            post(k, down: false)
        } else if tapAction != .nothing {
            DispatchQueue.main.async { self.onAction(tapAction) }
        }
    }

    /// Sends a keystroke tagged as ours, so neither this tap nor panespace's treats it as Caps+key.
    func post(_ k: KeyCombo, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: k.keyCode, keyDown: down) else { return }
        var flags: CGEventFlags = []
        if k.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if k.modifiers.contains(.control) { flags.insert(.maskControl) }
        if k.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if k.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if (0x7B...0x7E).contains(k.keyCode) { flags.insert([.maskNumericPad, .maskSecondaryFn]) }  // arrows
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: CapsLock.syntheticTag)
        e.post(tap: .cgSessionEventTap)
    }

    /// Types text by sending it as Unicode key events (20 UTF-16 units each).
    func type(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 20, units.count)])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                chunk.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                e.setIntegerValueField(.eventSourceUserData, value: CapsLock.syntheticTag)
                e.post(tap: .cgSessionEventTap)
            }
            i += 20
        }
    }

    private static func modifiers(_ f: CGEventFlags) -> Modifiers {
        var m: Modifiers = []
        if f.contains(.maskShift) { m.insert(.shift) }
        if f.contains(.maskControl) { m.insert(.control) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskCommand) { m.insert(.command) }
        return m
    }
}
