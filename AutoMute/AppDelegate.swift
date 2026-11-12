import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hardware = CoreAudioHardware()
    private let preferences = AutoMutePreferences()
    private var controller: AutoMuteController?
    private var menuBar: MenuBarController?
    private var verifier: MuteVerifier?
    private var signals: [any DispatchSourceSignal] = []
    private(set) var exitCode: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProbeLog.lifecycle.notice("AutoMuteを起動しました")
        installTerminationSignals()
        do {
            if CommandLine.arguments.contains("--verify-mute-once") {
                #if DEBUG
                ProbeLog.lifecycle.notice("一度限りのミュート検証を実行します")
                let target = try hardware.defaultOutput()
                let verifier = MuteVerifier(hardware: hardware)
                self.verifier = verifier
                verifier.verifyOnce(target: target) { [weak self] result in
                    guard result != .cancelled else { return }
                    self?.exitCode = result.succeeded ? 0 : 1
                    NSApplication.shared.terminate(nil)
                }
                #else
                ProbeLog.lifecycle.error("--verify-mute-onceはDebugビルド専用です")
                exitCode = 1
                NSApplication.shared.terminate(nil)
                #endif
            } else {
                let controller = AutoMuteController(hardware: hardware)
                self.controller = controller
                menuBar = MenuBarController(
                    onToggle: { [weak self] in self?.toggleAutoMute() },
                    onQuit: { NSApplication.shared.terminate(nil) }
                )
                setAutoMuteEnabled(preferences.isEnabled)
            }
        } catch {
            ProbeLog.lifecycle.error("起動失敗: \(String(describing: error), privacy: .public)")
            exitCode = 1
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        verifier?.cancel()
        menuBar?.remove()
        signals.forEach { $0.cancel() }
        signals.removeAll()
        ProbeLog.lifecycle.notice("監視とリスナーの終了処理を実行しました")
        // NSApplicationの通常終了は0で終了するため、検証結果を終了コードへ反映する。
        exit(exitCode)
    }

    private func toggleAutoMute() {
        guard let controller else { return }
        setAutoMuteEnabled(!controller.isRunning)
    }

    private func setAutoMuteEnabled(_ enabled: Bool) {
        guard let controller else { return }
        var failedToStart = false
        do {
            if enabled {
                try controller.start()
                ProbeLog.lifecycle.notice("自動ミュートをONにしました")
            } else {
                controller.stop()
                ProbeLog.lifecycle.notice("自動ミュートをOFFにしました。現在のミュート状態は変更しません")
            }
        } catch {
            controller.stop()
            failedToStart = true
            ProbeLog.lifecycle.error("自動ミュートの開始失敗。OFFで待機します: \(String(describing: error), privacy: .public)")
        }
        preferences.isEnabled = controller.isRunning
        menuBar?.update(isEnabled: controller.isRunning, failedToStart: failedToStart)
    }

    private func installTerminationSignals() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApplication.shared.terminate(nil) } }
            source.resume()
            signals.append(source)
        }
    }
}
