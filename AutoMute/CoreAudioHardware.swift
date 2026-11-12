import CoreAudio
import Foundation

struct AudioHardwareError: Error, CustomStringConvertible {
    let description: String

    init(_ message: String) { description = message }

    init(operation: String, object: AudioObjectID, selector: AudioObjectPropertySelector, status: OSStatus) {
        description = "\(operation): object=\(object) selector=\(audioCodeDescription(selector)) OSStatus=\(status) (\(audioCodeDescription(UInt32(bitPattern: status))))"
    }
}

@MainActor
protocol AudioObservation: AnyObject {
    func cancel() throws
}

@MainActor
protocol AudioHardwareAccess: AnyObject {
    func defaultOutput() throws -> AudioDeviceSnapshot
    func observeDefaultOutput(_ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation
    func canMute(_ device: AudioDeviceID) throws -> Bool
    func isMuted(_ device: AudioDeviceID) throws -> Bool
    func enableMute(_ device: AudioDeviceID) throws
    func observeMute(_ device: AudioDeviceID, _ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation
}

@MainActor
private final class CoreAudioObservation: AudioObservation {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private var active = true

    init(object: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping @MainActor () -> Void) throws {
        self.object = object
        self.address = address
        block = { _, _ in
            // Core Audioへの登録先をmainキューに固定している。
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &self.address, .main, block)
        guard status == noErr else {
            throw AudioHardwareError(operation: "リスナー登録失敗", object: object, selector: address.mSelector, status: status)
        }
    }

    func cancel() throws {
        guard active else { return }
        let status = AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        guard status == noErr else {
            throw AudioHardwareError(operation: "リスナー解除失敗", object: object, selector: address.mSelector, status: status)
        }
        active = false
    }
}

@MainActor
final class CoreAudioHardware: AudioHardwareAccess {
    private let system = AudioObjectID(kAudioObjectSystemObject)

    func defaultOutput() throws -> AudioDeviceSnapshot {
        let id = try readUInt32(system, kAudioHardwarePropertyDefaultOutputDevice)
        guard id != kAudioObjectUnknown else { throw AudioHardwareError("デフォルト出力が取得できません") }
        let uid = try readString(id, kAudioDevicePropertyDeviceUID)
        let name = try readString(id, kAudioObjectPropertyName)
        let transport = try readUInt32(id, kAudioDevicePropertyTransportType)
        let streams = try readIDs(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        let terminals = try streams.map { try readUInt32($0, kAudioStreamPropertyTerminalType) }
        guard try readUInt32(system, kAudioHardwarePropertyDefaultOutputDevice) == id else {
            throw AudioHardwareError("情報取得中にデフォルト出力が変わったため、判定を中断しました")
        }
        return AudioDeviceSnapshot(identity: .init(id: id, uid: uid), name: name, transport: transport, terminals: terminals)
    }

    func observeDefaultOutput(_ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation {
        try CoreAudioObservation(object: system, address: address(kAudioHardwarePropertyDefaultOutputDevice), handler: handler)
    }

    func canMute(_ device: AudioDeviceID) throws -> Bool {
        var property = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(device, &property, &settable), "書き込み可否の取得失敗", device, property.mSelector)
        return settable.boolValue
    }

    func isMuted(_ device: AudioDeviceID) throws -> Bool {
        try readUInt32(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput) != 0
    }

    func enableMute(_ device: AudioDeviceID) throws {
        var property = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        var enabled: UInt32 = 1
        try check(AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &enabled), "ミュート設定失敗", device, property.mSelector)
    }

    func observeMute(_ device: AudioDeviceID, _ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation {
        try CoreAudioObservation(object: device, address: address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput), handler: handler)
    }

    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String, _ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws {
        guard status == noErr else { throw AudioHardwareError(operation: operation, object: object, selector: selector, status: status) }
    }

    private func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> UInt32 {
        var property = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "数値プロパティ取得失敗", object, selector)
        guard size == MemoryLayout<UInt32>.size else { throw AudioHardwareError("数値プロパティのサイズが不正です") }
        return value
    }

    private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "文字列プロパティ取得失敗", object, selector)
        guard let value else { throw AudioHardwareError("文字列プロパティが空です") }
        return value.takeRetainedValue() as String
    }

    private func readIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        var property = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "配列サイズ取得失敗", object, selector)
        guard size > 0 else { return [] }
        let stride = UInt32(MemoryLayout<AudioObjectID>.stride)
        guard size % stride == 0 else { throw AudioHardwareError("デバイス配列のサイズが不正です") }
        var values = [AudioObjectID](repeating: 0, count: Int(size / stride))
        let capacity = size
        let status = values.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, bytes.baseAddress!)
        }
        try check(status, "配列プロパティ取得失敗", object, selector)
        guard size <= capacity, size % stride == 0 else { throw AudioHardwareError("取得したデバイス配列のサイズが不正です") }
        return Array(values.prefix(Int(size / stride)))
    }
}
