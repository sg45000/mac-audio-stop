import Foundation
import XCTest

@MainActor
final class AutoMutePreferencesTests: XCTestCase {
    func test初回起動はONにする() async throws {
        let name = "local.AutoMuteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(AutoMutePreferences(defaults: defaults).isEnabled)
    }

    func testOFFの選択を次回起動に引き継ぐ() async throws {
        let name = "local.AutoMuteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AutoMutePreferences(defaults: defaults)
        preferences.isEnabled = false
        XCTAssertFalse(AutoMutePreferences(defaults: defaults).isEnabled)
    }

    func test再度ONにした選択を保存する() async throws {
        let name = "local.AutoMuteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AutoMutePreferences(defaults: defaults)
        preferences.isEnabled = false
        preferences.isEnabled = true
        XCTAssertTrue(AutoMutePreferences(defaults: defaults).isEnabled)
    }
}
