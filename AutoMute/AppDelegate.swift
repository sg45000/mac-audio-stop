import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hardware = CoreAudioHardware()
    private var monitor: AudioOutputMonitor?
    private var verifier: MuteVerifier?
    private var signals: [any DispatchSourceSignal] = []
    private(set) var exitCode: Int32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProbeLog.lifecycle.notice("AutoMute技術検証を起動しました。自動ミュートは未接続です")
        installTerminationSignals()
        let monitor = AudioOutputMonitor(hardware: hardware)
        self.monitor = monitor
        do {
            try monitor.start()
            if CommandLine.arguments.contains("--verify-mute-once") {
                #if DEBUG
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
            }
        } catch {
            ProbeLog.lifecycle.error("起動失敗: \(String(describing: error), privacy: .public)")
            exitCode = 1
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        verifier?.cancel()
        signals.forEach { $0.cancel() }
        signals.removeAll()
        ProbeLog.lifecycle.notice("監視とリスナーの終了処理を実行しました")
        // NSApplicationの通常終了は0で終了するため、検証結果を終了コードへ反映する。
        exit(exitCode)
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
