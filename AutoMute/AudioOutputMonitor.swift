import Foundation

@MainActor
final class AudioOutputMonitor {
    private let hardware: any AudioHardwareAccess
    private var observation: (any AudioObservation)?
    private(set) var previous: AudioDeviceSnapshot?
    var onChange: ((AudioDeviceSnapshot?, AudioDeviceSnapshot) -> Void)?

    init(hardware: any AudioHardwareAccess) { self.hardware = hardware }

    func start() throws {
        guard observation == nil else { return }
        observation = try hardware.observeDefaultOutput { [weak self] in self?.refresh() }
        do {
            previous = try hardware.defaultOutput()
            ProbeLog.devices.notice("初期出力: \(self.previous!.logDescription, privacy: .public)。観測のみでミュートは実行しません")
        } catch {
            previous = nil
            ProbeLog.devices.error("初期出力取得失敗: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        guard let observation else { return }
        do { try observation.cancel() }
        catch { ProbeLog.devices.error("\(String(describing: error), privacy: .public)") }
        self.observation = nil
        previous = nil
    }

    private func refresh() {
        guard observation != nil else { return }
        do {
            let current = try hardware.defaultOutput()
            let old = previous
            previous = current
            guard old?.identity != current.identity else {
                ProbeLog.devices.debug("同じ出力の重複通知: id=\(current.identity.id)")
                return
            }
            let before = old?.logDescription ?? "未確定"
            ProbeLog.devices.notice("出力変更: 前=[\(before, privacy: .public)] 後=[\(current.logDescription, privacy: .public)]。観測のみ")
            onChange?(old, current)
        } catch {
            previous = nil
            ProbeLog.devices.error("出力取得失敗。前回状態を未確定に戻します: \(String(describing: error), privacy: .public)")
        }
    }
}
