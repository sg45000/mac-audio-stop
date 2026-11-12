import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        statusItem.button?.title = "AutoMute: \(state)"
        statusItem.button?.toolTip = failedToStart ? "監視を開始できませんでした。メニューから再度ONにできます" : "自動ミュート: \(state)"
        statusItem.button?.setAccessibilityLabel("AutoMute: 自動ミュート\(state)")
        toggleItem.title = isEnabled ? "自動ミュートをOFFにする" : "自動ミュートをONにする"
        errorItem.isHidden = !failedToStart
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func toggleEnabled() { onToggle() }
    @objc private func quit() { onQuit() }
}
