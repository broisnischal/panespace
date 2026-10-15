import AppKit
import CapsCore
import SwiftUI

/// Full-screen frosted overlay shown while Caps is held: blurs whatever is on screen and, for the
/// cheat sheet, lists every Caps key for the frontmost app. Click-through, never takes focus.
final class Overlay {
    private var panel: NSPanel?
    private var host: NSHostingView<AnyView>?
    private var generation = 0
    private(set) var isVisible = false

    /// `sections` nil = blur only.
    func show(sections: [CheatSection]?, app: String) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let panel = panel ?? makePanel()
        generation += 1
        panel.setFrame(screen.frame, display: false)
        host?.rootView = sections.map { AnyView(CheatSheetView(app: app, sections: $0, screen: screen.frame.size)) }
            ?? AnyView(Color.black.opacity(0.08))
        if !isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            Overlay.blurBehind(panel, radius: 48)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
                panel.animator().alphaValue = 1
            }
        }
        isVisible = true
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        let g = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.generation == g, self?.isVisible == false { panel.orderOut(nil) }
        })
    }

    /// Window-server blur of everything behind the panel (what iTerm2 uses for its blurred background).
    /// More reliable than NSVisualEffectView alone for a screen-saver-level panel. Fails soft.
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetBlur = @convention(c) (Int32, Int32, Int32) -> Int32
    private static let cgs: (MainConnection, SetBlur)? = {
        let h = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let c = dlsym(h, "CGSMainConnectionID"), let b = dlsym(h, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (unsafeBitCast(c, to: MainConnection.self), unsafeBitCast(b, to: SetBlur.self))
    }()

    private static func blurBehind(_ w: NSWindow, radius: Int32) {
        guard let (connection, setBlur) = cgs, w.windowNumber > 0 else { return }
        _ = setBlur(connection(), Int32(w.windowNumber), radius)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.level = .screenSaver  // above the menu bar, Dock and full-screen apps
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow  // blurs the other apps' windows; Reduce Transparency makes it solid
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        p.contentView = blur
        panel = p
        self.host = host
        return p
    }
}

struct CheatSheetView: View {
    let app: String
    let sections: [CheatSection]
    let screen: CGSize

    /// Splits long sections and fills columns top to bottom, so the sheet reads like a page.
    private var columns: [[CheatSection]] {
        let maxRows = max(8, Int((screen.height - 260) / 31))
        var chunks: [CheatSection] = []
        for s in sections {
            var rest = s.rows[...]
            var title = s.title
            while !rest.isEmpty {
                chunks.append(CheatSection(title: title, rows: Array(rest.prefix(maxRows))))
                rest = rest.dropFirst(maxRows)
                title = ""
            }
        }
        var cols: [[CheatSection]] = [[]]
        var used = 0
        for c in chunks {
            let cost = c.rows.count + (c.title.isEmpty ? 0 : 2)
            if used + cost > maxRows + 2, !cols[cols.count - 1].isEmpty {
                cols.append([])
                used = 0
            }
            cols[cols.count - 1].append(c)
            used += cost
        }
        return cols
    }

    var body: some View {
        let cols = columns
        let columnWidth = min(300, (screen.width - 160) / CGFloat(max(cols.count, 1)) - 32)
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "capslock.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("Caps")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(app)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 40)
                Text("Hold Caps and press a key · release to close")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            HStack(alignment: .top, spacing: 40) {
                ForEach(cols.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(cols[i].indices, id: \.self) { j in SectionView(section: cols[i][j]) }
                    }
                    .frame(width: columnWidth, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(44)
        .frame(maxWidth: min(screen.width - 80, CGFloat(cols.count) * (columnWidth + 40) + 48))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.16))
        .environment(\.colorScheme, .dark)
    }
}

private struct SectionView: View {
    let section: CheatSection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 3)
            }
            ForEach(section.rows.indices, id: \.self) { i in
                let row = section.rows[i]
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(row.keys.split(separator: " ").map(String.init), id: \.self) { KeyCap(text: $0) }
                    }
                    .frame(width: 92, alignment: .leading)
                    Text(row.label)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 23)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
    }
}
