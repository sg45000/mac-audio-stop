import CoreAudio
import IOKit.audio
import XCTest

final class DeviceClassificationTests: XCTestCase {
    func testBluetoothとBluetoothLEを識別する() {
        for transport in [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE] {
            XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: []), .bluetooth)
        }
    }

    func test新旧のスピーカー端子を内蔵Transportと組み合わせる() {
        for terminal in [kAudioStreamTerminalTypeSpeaker, UInt32(OUTPUT_SPEAKER)] {
            XCTAssertEqual(OutputDeviceKind.classify(transport: kAudioDeviceTransportTypeBuiltIn, terminals: [terminal]), .builtInSpeaker)
            XCTAssertEqual(OutputDeviceKind.classify(transport: kAudioDeviceTransportTypeUSB, terminals: [terminal]), .other)
        }
    }

    func test内蔵ヘッドホンと不明な端子をスピーカー扱いしない() {
        let transport = kAudioDeviceTransportTypeBuiltIn
        XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: [kAudioStreamTerminalTypeHeadphones]), .other)
        XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: [UInt32(OUTPUT_HEADPHONES)]), .other)
        XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: []), .unknown)
        XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: [0]), .unknown)
        XCTAssertEqual(OutputDeviceKind.classify(transport: transport, terminals: [UInt32(OUTPUT_SPEAKER), UInt32(OUTPUT_HEADPHONES)]), .other)
    }
}

@MainActor
final class OutputMonitorTests: XCTestCase {
    func test起動時は初期状態を保存し操作しない() async throws {
        let hardware = FakeAudioHardware()
        let monitor = AudioOutputMonitor(hardware: hardware)
        var changes = 0
        monitor.onChange = { _, _ in changes += 1 }
        try monitor.start()
        XCTAssertEqual(monitor.previous, hardware.output)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(hardware.muteWrites, 0)
        monitor.stop()
        XCTAssertTrue(hardware.outputObservation?.cancelled == true)
    }

    func test重複を除外し前回のBluetooth情報を保持する() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let monitor = AudioOutputMonitor(hardware: hardware)
        var before: AudioDeviceSnapshot?
        var changes = 0
        monitor.onChange = { old, _ in before = old; changes += 1 }
        try monitor.start()
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.notifyOutput()
        XCTAssertEqual(before, .bluetooth)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(hardware.muteWrites, 0)
        monitor.stop()
    }

    func test取得失敗後は古い出力からの遷移を推測しない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let monitor = AudioOutputMonitor(hardware: hardware)
        try monitor.start()
        hardware.failOutput = true
        hardware.notifyOutput()
        XCTAssertNil(monitor.previous)
        hardware.failOutput = false
        hardware.output = .speaker
        var before: AudioDeviceSnapshot? = .bluetooth
        monitor.onChange = { old, _ in before = old }
        hardware.notifyOutput()
        XCTAssertNil(before)
        XCTAssertEqual(monitor.previous, .speaker)
        monitor.stop()
    }

    func testID再利用時もUIDが変われば別デバイスとして扱う() async throws {
        let hardware = FakeAudioHardware()
        let monitor = AudioOutputMonitor(hardware: hardware)
        try monitor.start()
        var changes = 0
        monitor.onChange = { _, _ in changes += 1 }
        hardware.output = .init(identity: .init(id: 1, uid: "test-new-uid"), name: "検証用出力", transport: kAudioDeviceTransportTypeUSB, terminals: [])
        hardware.notifyOutput()
        XCTAssertEqual(changes, 1)
        monitor.stop()
    }

    func test停止後に届いたコールバックを無視する() async throws {
        let hardware = FakeAudioHardware()
        let monitor = AudioOutputMonitor(hardware: hardware)
        try monitor.start()
        monitor.stop()
        hardware.notifyOutput()
        XCTAssertNil(monitor.previous)
    }
}

@MainActor
final class MuteVerifierTests: XCTestCase {
    func test通知後の読み戻しで成功を確認しリスナーを解除する() async {
        let hardware = FakeAudioHardware()
        let verifier = MuteVerifier(hardware: hardware)
        var result: MuteVerificationResult?
        verifier.verifyOnce(target: .speaker) { result = $0 }
        XCTAssertNil(result)
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertTrue(hardware.observedBeforeWrite)
        hardware.muted = true
        hardware.notifyMute()
        XCTAssertEqual(result, .confirmed)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
        hardware.notifyMute()
        XCTAssertEqual(hardware.muteWrites, 1)
    }

    func test既にミュート済みなら書き込まない() async {
        let hardware = FakeAudioHardware()
        hardware.muted = true
        let verifier = MuteVerifier(hardware: hardware)
        var result: MuteVerificationResult?
        verifier.verifyOnce(target: .speaker) { result = $0 }
        XCTAssertEqual(result, .alreadyMuted)
        XCTAssertEqual(hardware.muteWrites, 0)
    }

    func test非対応と対象外デバイスには書き込まない() async {
        let hardware = FakeAudioHardware()
        let verifier = MuteVerifier(hardware: hardware)
        var results: [MuteVerificationResult] = []
        verifier.verifyOnce(target: .bluetooth) { results.append($0) }
        hardware.muteSupported = false
        verifier.verifyOnce(target: .speaker) { results.append($0) }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { !$0.succeeded })
        XCTAssertEqual(hardware.muteWrites, 0)
    }

    func test書き込み直前に出力が変わったら中止する() async {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let verifier = MuteVerifier(hardware: hardware)
        var result: MuteVerificationResult?
        verifier.verifyOnce(target: .speaker) { result = $0 }
        XCTAssertTrue(result?.succeeded == false)
        XCTAssertEqual(hardware.muteWrites, 0)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
    }

    func test設定失敗でも終了処理と次回検証を実行できる() async {
        let hardware = FakeAudioHardware()
        hardware.failWrite = true
        let verifier = MuteVerifier(hardware: hardware)
        var results: [MuteVerificationResult] = []
        verifier.verifyOnce(target: .speaker) { results.append($0) }
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].succeeded)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
        hardware.failWrite = false
        verifier.verifyOnce(target: .speaker) { results.append($0) }
        hardware.muted = true
        hardware.notifyMute()
        XCTAssertEqual(results.last, .confirmed)
    }

    func test通知がなくても期限時に読み戻して確認する() async {
        let hardware = FakeAudioHardware()
        let verifier = MuteVerifier(hardware: hardware, timeout: 0)
        let completed = expectation(description: "期限時にミュート済みと確認する")
        verifier.verifyOnce(target: .speaker) { result in
            XCTAssertEqual(result, .confirmed)
            completed.fulfill()
        }
        hardware.muted = true
        await fulfillment(of: [completed], timeout: 1)
    }

    func test期限超過で再書き込みしない() async {
        let hardware = FakeAudioHardware()
        let verifier = MuteVerifier(hardware: hardware, timeout: 0)
        let completed = expectation(description: "期限超過を返す")
        verifier.verifyOnce(target: .speaker) { result in
            XCTAssertEqual(result, .timedOut)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
    }

    func test中止時にリスナーと待機を解除する() async {
        let hardware = FakeAudioHardware()
        let verifier = MuteVerifier(hardware: hardware)
        var result: MuteVerificationResult?
        verifier.verifyOnce(target: .speaker) { result = $0 }
        verifier.cancel()
        hardware.muted = true
        hardware.notifyMute()
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
    }
}

extension AudioDeviceSnapshot {
    static let speaker = Self(identity: .init(id: 1, uid: "test-speaker"), name: "検証用内蔵出力", transport: kAudioDeviceTransportTypeBuiltIn, terminals: [UInt32(OUTPUT_SPEAKER)])
    static let bluetooth = Self(identity: .init(id: 2, uid: "test-bluetooth"), name: "検証用Bluetooth出力", transport: kAudioDeviceTransportTypeBluetooth, terminals: [kAudioStreamTerminalTypeHeadphones])
}

@MainActor
final class FakeObservation: AudioObservation {
    var cancelled = false
    func cancel() throws { cancelled = true }
}

@MainActor
final class FakeAudioHardware: AudioHardwareAccess {
    var output: AudioDeviceSnapshot = .speaker
    var failOutput = false
    var failWrite = false
    var muted = false
    var muteSupported = true
    var muteWrites = 0
    var observedBeforeWrite = false
    var outputObservation: FakeObservation?
    var muteObservation: FakeObservation?
    private var outputHandler: (@MainActor () -> Void)?
    private var muteHandler: (@MainActor () -> Void)?

    func defaultOutput() throws -> AudioDeviceSnapshot {
        if failOutput { throw AudioHardwareError("検証用の取得失敗") }
        return output
    }

    func observeDefaultOutput(_ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation {
        outputHandler = handler
        let observation = FakeObservation()
        outputObservation = observation
        return observation
    }

    func canMute(_ device: AudioDeviceID) throws -> Bool { muteSupported }
    func isMuted(_ device: AudioDeviceID) throws -> Bool { muted }
    func enableMute(_ device: AudioDeviceID) throws {
        observedBeforeWrite = muteObservation != nil
        muteWrites += 1
        if failWrite { throw AudioHardwareError("検証用の設定失敗") }
    }

    func observeMute(_ device: AudioDeviceID, _ handler: @escaping @MainActor () -> Void) throws -> any AudioObservation {
        muteHandler = handler
        let observation = FakeObservation()
        muteObservation = observation
        return observation
    }

    func notifyOutput() { outputHandler?() }
    func notifyMute() { muteHandler?() }
}
