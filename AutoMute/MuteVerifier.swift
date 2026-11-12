import Foundation

enum MuteVerificationResult: Equatable {
    case alreadyMuted
    case confirmed
    case timedOut
    case failed(String)
    case cancelled

    var succeeded: Bool { self == .alreadyMuted || self == .confirmed }

    var logDescription: String {
        switch self {
        case .alreadyMuted: "既にミュート済み（書き込みなし）"
        case .confirmed: "読み戻しでミュートONを確認"
        case .timedOut: "期限内にミュートONを確認できませんでした"
        case .failed(let reason): reason
        case .cancelled: "中止"
        }
    }
}

@MainActor
final class MuteVerifier {
    private let hardware: any AudioHardwareAccess
    private let timeout: TimeInterval
    private var observation: (any AudioObservation)?
    private var deadline: DispatchWorkItem?
    private var completion: ((MuteVerificationResult) -> Void)?
    private var target: AudioDeviceSnapshot?
    private var requestTime: ContinuousClock.Instant?

    init(hardware: any AudioHardwareAccess, timeout: TimeInterval = 1) {
        self.hardware = hardware
        self.timeout = timeout
    }

    func verifyOnce(target: AudioDeviceSnapshot, completion: @escaping (MuteVerificationResult) -> Void) {
        guard self.completion == nil else {
            completion(.failed("ミュート検証は既に実行中です"))
            return
        }
        self.completion = completion
        self.target = target
        do {
            guard target.kind == .builtInSpeaker else { throw AudioHardwareError("内蔵スピーカー以外はミュートしません") }
            guard try hardware.canMute(target.identity.id) else { throw AudioHardwareError("Main要素のミュート機能が未対応、または書き込み不可です") }
            guard try !hardware.isMuted(target.identity.id) else {
                finish(.alreadyMuted)
                return
            }
            observation = try hardware.observeMute(target.identity.id) { [weak self] in self?.confirm(isDeadline: false) }
            let current = try hardware.defaultOutput()
            guard current.identity == target.identity, current.kind == .builtInSpeaker else {
                throw AudioHardwareError("書き込み直前に出力が変わったため、ミュートを中止しました")
            }
            requestTime = .now
            ProbeLog.mute.notice("ミュート設定要求: \(target.logDescription, privacy: .public)")
            try hardware.enableMute(target.identity.id)
            guard self.completion != nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.confirm(isDeadline: true) }
            }
            deadline = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        } catch {
            finish(.failed(String(describing: error)))
        }
    }

    func cancel() { finish(.cancelled) }

    private func confirm(isDeadline: Bool) {
        guard let target, completion != nil else { return }
        do {
            if try hardware.isMuted(target.identity.id) {
                finish(.confirmed)
            } else if isDeadline {
                finish(.timedOut)
            }
        } catch {
            finish(.failed(String(describing: error)))
        }
    }

    private func finish(_ result: MuteVerificationResult) {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        deadline = nil
        if let observation {
            do { try observation.cancel() }
            catch { ProbeLog.mute.error("\(String(describing: error), privacy: .public)") }
        }
        observation = nil
        target = nil
        let elapsed = requestTime.map { String(format: "%.3f ms", $0.duration(to: .now) / .milliseconds(1)) } ?? "書き込みなし"
        requestTime = nil
        if result.succeeded {
            ProbeLog.mute.notice("ミュート処理成功: \(result.logDescription, privacy: .public) 設定要求からの経過=\(elapsed, privacy: .public)")
        } else if result == .cancelled {
            ProbeLog.mute.notice("ミュート反映の確認を中止しました")
        } else {
            ProbeLog.mute.error("ミュート処理失敗: \(result.logDescription, privacy: .public) 設定要求からの経過=\(elapsed, privacy: .public)")
        }
        completion(result)
    }
}
