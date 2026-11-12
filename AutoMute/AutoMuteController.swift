import Foundation

func shouldAutoMute(from previous: AudioDeviceSnapshot?, to current: AudioDeviceSnapshot) -> Bool {
    previous?.kind == .bluetooth && current.kind == .builtInSpeaker
}

@MainActor
final class AutoMuteController {
    private let monitor: AudioOutputMonitor
    private let verifier: MuteVerifier
    private var isRunning = false

    init(hardware: any AudioHardwareAccess) {
        monitor = AudioOutputMonitor(hardware: hardware)
        verifier = MuteVerifier(hardware: hardware)
        monitor.onChange = { [weak self] previous, current in
            self?.handleChange(from: previous, to: current)
        }
    }

    func start() throws {
        guard !isRunning else { return }
        isRunning = true
        do {
            try monitor.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        isRunning = false
        monitor.stop()
        verifier.cancel()
    }

    private func handleChange(from previous: AudioDeviceSnapshot?, to current: AudioDeviceSnapshot) {
        guard isRunning else { return }
        // 出力が変わったら以前の確認待ちを終了し、今回の遷移を独立して判定する。
        verifier.cancel()
        guard shouldAutoMute(from: previous, to: current) else {
            let previousKind = previous?.kind.rawValue ?? "未確定"
            ProbeLog.mute.debug("自動ミュート対象外: \(previousKind, privacy: .public) → \(current.kind.rawValue, privacy: .public)")
            return
        }
        ProbeLog.mute.notice("Bluetoothから内蔵スピーカーへの変更を検出し、自動ミュートを実行します")
        verifier.verifyOnce(target: current) { _ in
            // 結果の記録はMuteVerifierが担当し、成否にかかわらず監視を継続する。
        }
    }
}
