import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let errorItem = NSMenuItem(title: "監視を開始できませんでした", action: nil, keyEquivalent: "")
    private let onToggle: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        toggleItem.target = self
        toggleItem.action = #selector(toggleEnabled)
        errorItem.isEnabled = false
        errorItem.isHidden = true
        menu.addItem(toggleItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "AutoMuteを終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        update(isEnabled: false)
    }

    func update(isEnabled: Bool, failedToStart: Bool = false) {
        let state = isEnabled ? "ON" : "OFF"
        statusItem.button?.title = ""
        statusItem.button?.image = Self.makeStatusImage(isEnabled: isEnabled)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = failedToStart ? "監視を開始できませんでした。メニューから再度ONにできます" : "自動ミュート: \(state)"
        statusItem.button?.setAccessibilityLabel("AutoMute: 自動ミュート\(state)")
        toggleItem.title = isEnabled ? "自動ミュートをOFFにする" : "自動ミュートをONにする"
        errorItem.isHidden = !failedToStart
    }

    private static func makeStatusImage(isEnabled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current,
                  let speaker = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil) else { return false }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            let scale = min(15 / speaker.size.width, 15 / speaker.size.height)
            let size = NSSize(width: speaker.size.width * scale, height: speaker.size.height * scale)
            speaker.draw(in: NSRect(x: (15 - size.width) / 2, y: (15 - size.height) / 2, width: size.width, height: size.height))

            let badgeRect = NSRect(x: 10.5, y: 10.5, width: 7, height: 7)
            context.compositingOperation = .clear
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -0.6, dy: -0.6)).fill()
            context.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if isEnabled {
                NSBezierPath(ovalIn: badgeRect).fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 12.1, y: 14.1))
                check.line(to: NSPoint(x: 13.4, y: 12.8))
                check.line(to: NSPoint(x: 16, y: 15.4))
                check.lineWidth = 1.1
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                context.compositingOperation = .clear
                check.stroke()
            } else {
                let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 0.6, dy: 0.6))
                ring.lineWidth = 1.2
                ring.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func toggleEnabled() { onToggle() }
    @objc private func quit() { onQuit() }
}
