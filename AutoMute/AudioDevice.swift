import CoreAudio
import Foundation
import IOKit.audio

enum OutputDeviceKind: String, Sendable {
    case bluetooth
    case builtInSpeaker
    case other
    case unknown

    static func classify(transport: UInt32, terminals: [UInt32]) -> Self {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeBuiltIn:
            guard !terminals.isEmpty else { return .unknown }
            let speakers = [kAudioStreamTerminalTypeSpeaker, UInt32(OUTPUT_SPEAKER)]
            if terminals.allSatisfy({ speakers.contains($0) }) { return .builtInSpeaker }
            if terminals.contains(kAudioStreamTerminalTypeUnknown) { return .unknown }
            return .other
        case kAudioDeviceTransportTypeUnknown:
            return .unknown
        default:
            return .other
        }
    }
}

struct AudioDeviceIdentity: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
}

struct AudioDeviceSnapshot: Equatable, Sendable {
    let identity: AudioDeviceIdentity
    let name: String
    let transport: UInt32
    let terminals: [UInt32]

    var kind: OutputDeviceKind {
        .classify(transport: transport, terminals: terminals)
    }

    var logDescription: String {
        let terminalText = terminals.map(audioCodeDescription).joined(separator: ", ")
        return "id=\(identity.id) name=\(name) kind=\(kind.rawValue) transport=\(audioCodeDescription(transport)) terminals=[\(terminalText)]"
    }
}

func audioCodeDescription(_ value: UInt32) -> String {
    let bytes = (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    let hex = String(format: "0x%08X", value)
    guard bytes.allSatisfy({ (32...126).contains($0) }) else { return hex }
    return "\(hex) ('\(String(bytes: bytes, encoding: .ascii)!)')"
}
