import CoreAudio
import XCTest

final class AutoMutePolicyTests: XCTestCase {
    func testBluetoothから内蔵スピーカーへの変更だけを対象にする() {
        let cases: [(AudioDeviceSnapshot?, AudioDeviceSnapshot, Bool)] = [
            (nil, .speaker, false),
            (.bluetooth, .speaker, true),
            (.bluetoothLE, .speaker, true),
            (.speaker, .bluetooth, false),
            (.speaker, .display, false),
            (.bluetooth, .anotherBluetooth, false),
            (.bluetooth, .bluetoothLE, false),
            (.usb, .speaker, false),
            (.bluetooth, .display, false),
            (.bluetooth, .wiredHeadphones, false),
            (.unknown, .speaker, false),
            (.bluetooth, .unknown, false),
            (.speaker, .speaker, false),
            (.bluetooth, .usb, false),
        ]
        for (previous, current, expected) in cases {
            XCTAssertEqual(shouldAutoMute(from: previous, to: current), expected, "\(previous?.name ?? "初期状態") → \(current.name)")
        }
    }
}

@MainActor
final class AutoMuteFlowTests: XCTestCase {
    func test内蔵スピーカーで起動してもミュートしない() async throws {
        let hardware = FakeAudioHardware()
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 0)
        XCTAssertFalse(hardware.muted)
        controller.stop()
    }

    func test出力変更で一度ミュートし再接続しても解除しない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertTrue(hardware.observedBeforeWrite)
        hardware.muted = true
        hardware.notifyMute()
        hardware.output = .bluetooth
        hardware.notifyOutput()
        XCTAssertTrue(hardware.muted)
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertFalse(hardware.outputObservation!.cancelled)
        controller.stop()
    }

    func testBluetoothLEからの変更もミュートする() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetoothLE
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        controller.stop()
    }

    func testユーザーのミュート解除後に重複通知が来ても再ミュートしない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.muted = true
        hardware.notifyMute()
        hardware.muted = false
        hardware.notifyOutput()
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertFalse(hardware.muted)
        controller.stop()
    }

    func testUSBを経由した変更では古いBluetooth情報でミュートしない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .usb
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 0)
        controller.stop()
    }

    func test反映確認中に再接続しても次の切り替えを処理できる() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        let firstObservation = hardware.muteObservation
        hardware.output = .bluetooth
        hardware.notifyOutput()
        XCTAssertTrue(firstObservation?.cancelled == true)
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 2)
        hardware.muted = true
        hardware.notifyMute()
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
        controller.stop()
    }

    func testミュート失敗後も監視し同じ通知では再試行しない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        hardware.failWrite = true
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        hardware.failWrite = false
        hardware.output = .bluetooth
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.muted = true
        hardware.notifyMute()
        XCTAssertEqual(hardware.muteWrites, 2)
        XCTAssertFalse(hardware.outputObservation!.cancelled)
        controller.stop()
    }

    func test出力取得失敗をまたいだ変更ではミュートしない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.failOutput = true
        hardware.notifyOutput()
        hardware.failOutput = false
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 0)
        hardware.output = .bluetooth
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        controller.stop()
    }

    func test接続と切断を繰り返しても各変更を処理する() async throws {
        let hardware = FakeAudioHardware()
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        for _ in 0..<10 {
            hardware.output = .bluetooth
            hardware.notifyOutput()
            hardware.muted = false
            hardware.output = .speaker
            hardware.notifyOutput()
            hardware.muted = true
            hardware.notifyMute()
        }
        XCTAssertEqual(hardware.muteWrites, 10)
        XCTAssertFalse(hardware.outputObservation!.cancelled)
        controller.stop()
    }

    func test停止時に監視と確認待ちを解除する() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        controller.stop()
        hardware.output = .bluetooth
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.notifyMute()
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertTrue(hardware.outputObservation?.cancelled == true)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
    }

    func testOFF中の変更とON再開直後にはミュートしない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        controller.stop()
        XCTAssertFalse(controller.isRunning)
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 0)
        try controller.start()
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(hardware.muteWrites, 0)
        hardware.output = .bluetooth
        hardware.notifyOutput()
        hardware.output = .speaker
        hardware.notifyOutput()
        XCTAssertEqual(hardware.muteWrites, 1)
        controller.stop()
    }

    func testOFFで確認待ちを取り消しても既存のミュートは解除しない() async throws {
        let hardware = FakeAudioHardware()
        hardware.output = .bluetooth
        let controller = AutoMuteController(hardware: hardware)
        try controller.start()
        hardware.output = .speaker
        hardware.notifyOutput()
        hardware.muted = true
        controller.stop()
        hardware.notifyMute()
        XCTAssertFalse(controller.isRunning)
        XCTAssertTrue(hardware.muted)
        XCTAssertEqual(hardware.muteWrites, 1)
        XCTAssertTrue(hardware.muteObservation?.cancelled == true)
    }

    func test再開に失敗したらOFFを維持し再度ONにできる() async throws {
        let hardware = FakeAudioHardware()
        let controller = AutoMuteController(hardware: hardware)
        hardware.failOutputObservation = true
        XCTAssertThrowsError(try controller.start())
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(hardware.muteWrites, 0)
        hardware.failOutputObservation = false
        try controller.start()
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(hardware.muteWrites, 0)
        controller.stop()
    }
}

private extension AudioDeviceSnapshot {
    static let bluetoothLE = Self(identity: .init(id: 3, uid: "test-ble"), name: "検証用Bluetooth LE出力", transport: kAudioDeviceTransportTypeBluetoothLE, terminals: [])
    static let anotherBluetooth = Self(identity: .init(id: 4, uid: "test-another-bluetooth"), name: "検証用の別のBluetooth出力", transport: kAudioDeviceTransportTypeBluetooth, terminals: [])
    static let usb = Self(identity: .init(id: 5, uid: "test-usb"), name: "検証用USB出力", transport: kAudioDeviceTransportTypeUSB, terminals: [])
    static let display = Self(identity: .init(id: 6, uid: "test-display"), name: "検証用モニター出力", transport: kAudioDeviceTransportTypeDisplayPort, terminals: [])
    static let wiredHeadphones = Self(identity: .init(id: 7, uid: "test-wired-headphones"), name: "検証用有線ヘッドホン", transport: kAudioDeviceTransportTypeBuiltIn, terminals: [kAudioStreamTerminalTypeHeadphones])
    static let unknown = Self(identity: .init(id: 8, uid: "test-unknown"), name: "検証用の不明な出力", transport: kAudioDeviceTransportTypeUnknown, terminals: [])
}
