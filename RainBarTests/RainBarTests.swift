import XCTest
@testable import RainBar

@MainActor
final class RainBarTests: XCTestCase {
    func testSettingsStoreUsesDefaultsWhenNoValuesExist() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.settings, .defaults)
        XCTAssertEqual(store.mode, .rain)
    }

    func testFullscreenRestoresBothStatesWithoutSavingPreset() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)
        XCTAssertFalse(store.isFullscreen)

        store.isFullscreen = true
        let restarted = RainSettingsStore(userDefaults: defaults)
        XCTAssertTrue(restarted.isFullscreen)

        restarted.isFullscreen = false
        XCTAssertFalse(RainSettingsStore(userDefaults: defaults).isFullscreen)
    }

    func testFullscreenIsIndependentOfPresets() throws {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)
        let originalSettings = store.settings
        let preset = try XCTUnwrap(store.savePreset(named: "Weather"))

        store.isFullscreen = true
        XCTAssertEqual(store.settings, originalSettings)
        store.loadPreset(id: preset.id)
        XCTAssertTrue(store.isFullscreen)
        store.loadPreset(id: RainPreset.defaultID)
        XCTAssertTrue(store.isFullscreen)
        store.updatePreset(id: preset.id)
        store.isFullscreen = false
        store.loadPreset(id: preset.id)
        XCTAssertFalse(store.isFullscreen)
    }

    func testSavedPresetPersistsSettings() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)

        store.mode = .snow
        store.settings.opacity = 0.7
        store.settings.snowFade = 0.8
        store.settings.splashOpacity = 0.35
        store.settings.rainAmount = 0.9
        store.settings.speed = 2.25
        store.settings.trailLength = 36.0
        store.settings.trailLengthVariation = 0.8
        store.settings.trailThickness = 2.7
        store.settings.rainColor = RainColor(red: 0.25, green: 0.5, blue: 0.75)
        store.isFullscreen = true
        store.settings.angle = 27.0
        store.savePreset(named: "Saved Snow")

        let restoredStore = RainSettingsStore(userDefaults: defaults)
        XCTAssertEqual(restoredStore.mode, .snow)
        XCTAssertEqual(restoredStore.settings.opacity, 0.7)
        XCTAssertEqual(restoredStore.settings.snowFade, 0.8)
        XCTAssertEqual(restoredStore.settings.splashOpacity, 0.35)
        XCTAssertEqual(restoredStore.settings.rainAmount, 0.9)
        XCTAssertEqual(restoredStore.settings.speed, 2.25)
        XCTAssertEqual(restoredStore.settings.trailLength, 36.0)
        XCTAssertEqual(restoredStore.settings.trailLengthVariation, 0.8)
        XCTAssertEqual(restoredStore.settings.trailThickness, 2.7)
        XCTAssertEqual(restoredStore.settings.rainColor, RainColor(red: 0.25, green: 0.5, blue: 0.75))
        XCTAssertTrue(restoredStore.isFullscreen)
        XCTAssertEqual(restoredStore.settings.angle, 27.0)
    }

    func testDefaultPresetCannotBeDeleted() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)

        store.deletePreset(id: RainPreset.defaultID)
        store.settings.rainAmount = 0.25
        store.updatePreset(id: RainPreset.defaultID)

        XCTAssertEqual(store.presets, [.defaultPreset()])
    }

    func testCustomPresetsSaveLoadAndDelete() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)

        store.settings.rainAmount = 0.75
        store.settings.rainColor = RainColor(red: 0.1, green: 0.2, blue: 0.3)
        let preset = store.savePreset(named: "Storm")!

        store.settings.rainAmount = 0.1
        store.settings.rainColor = RainColor(red: 1, green: 1, blue: 1)
        store.loadPreset(id: preset.id)

        XCTAssertEqual(store.settings.rainAmount, 0.75)
        XCTAssertEqual(store.settings.rainColor, RainColor(red: 0.1, green: 0.2, blue: 0.3))

        let restoredStore = RainSettingsStore(userDefaults: defaults)
        XCTAssertEqual(restoredStore.presets.map(\.name), ["Default", "Storm"])

        restoredStore.deletePreset(id: preset.id)
        XCTAssertEqual(restoredStore.presets, [.defaultPreset()])
    }

    func testCustomPresetCanBeOverwritten() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)

        store.settings.rainAmount = 0.2
        let preset = store.savePreset(named: "Light")!

        store.settings.rainAmount = 0.6
        store.updatePreset(id: preset.id)
        store.settings.rainAmount = 0.1
        store.loadPreset(id: preset.id)

        XCTAssertEqual(store.settings.rainAmount, 0.6)

        store.settings.rainAmount = 0.8
        let overwritten = store.savePreset(named: " LIGHT ")
        XCTAssertEqual(overwritten?.id, preset.id)
        XCTAssertEqual(overwritten?.name, "Light")
        XCTAssertEqual(store.customPresets.count, 1)
        XCTAssertEqual(RainSettingsStore(userDefaults: defaults).settings.rainAmount, 0.8)
    }

    func testOlderPresetsDefaultToCurrentSnowFade() throws {
        let encoded = try JSONEncoder().encode(RainSettings.defaults)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "snowFade")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let restored = try JSONDecoder().decode(RainSettings.self, from: data)

        XCTAssertEqual(restored, .defaults)
        XCTAssertEqual(restored.snowFade, 0.5)
    }

    func testPresetsAreIsolatedByModeAndPersist() throws {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)
        store.settings.rainAmount = 0.2
        let rain = try XCTUnwrap(store.savePreset(named: "Storm"))
        store.mode = .snow
        XCTAssertEqual(store.presets.map(\.name), ["Default"])
        store.settings.rainAmount = 0.8
        let snow = try XCTUnwrap(store.savePreset(named: "Storm"))
        XCTAssertNotEqual(rain.id, snow.id)
        XCTAssertEqual(store.presets.map(\.id), [RainPreset.defaultID, snow.id])

        store.loadPreset(id: rain.id)
        XCTAssertEqual(store.settings.rainAmount, 0.8)
        store.updatePreset(id: rain.id)
        store.deletePreset(id: rain.id)

        let restored = RainSettingsStore(userDefaults: defaults)
        XCTAssertEqual(restored.presets.map(\.id), [RainPreset.defaultID, snow.id])
        restored.mode = .rain
        XCTAssertEqual(restored.presets.map(\.id), [RainPreset.defaultID, rain.id])
        restored.loadPreset(id: rain.id)
        XCTAssertEqual(restored.settings.rainAmount, 0.2)
        restored.mode = .snow
        restored.loadPreset(id: snow.id)
        XCTAssertEqual(restored.settings.rainAmount, 0.8)
    }

    func testLegacyPresetsAreDeleted() throws {
        let defaults = makeUserDefaults()
        defaults.set(try JSONEncoder().encode([RainPreset.defaultPreset()]), forKey: "rain.customPresets")
        let store = RainSettingsStore(userDefaults: defaults)
        XCTAssertNil(defaults.object(forKey: "rain.customPresets"))
        XCTAssertTrue(store.customPresets.isEmpty)
    }

    func testMenuExpansionReversesFromCurrentHeight() {
        var reportedHeight: CGFloat = 0
        let layout = MenuLayout { reportedHeight = $0 }
        layout.setHeaderHeight(70)
        layout.setControlsHeight(400)
        layout.setExpanded(true, animated: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let partialHeight = layout.visibleControlsHeight
        XCTAssertGreaterThan(partialHeight, 0)
        XCTAssertLessThan(partialHeight, 400)
        XCTAssertEqual(reportedHeight, 70 + partialHeight)

        layout.setExpanded(false, animated: true)
        XCTAssertEqual(layout.visibleControlsHeight, partialHeight)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        XCTAssertEqual(layout.visibleControlsHeight, 0)
        XCTAssertEqual(reportedHeight, 70)

        layout.setExpanded(true, animated: false)
        XCTAssertEqual(layout.visibleControlsHeight, 400)
        XCTAssertEqual(reportedHeight, 470)
    }

    func testModeSwitchAndRelaunchRestoreSavedPresetInsteadOfEdits() throws {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)
        store.settings.rainAmount = 0.2
        let rain = try XCTUnwrap(store.savePreset(named: "Rain Choice"))
        store.settings.rainAmount = 0.9
        store.mode = .snow
        XCTAssertEqual(store.selectedPresetID, RainPreset.defaultID)
        XCTAssertEqual(store.settings, .defaults(for: .snow))
        store.settings.opacity = 0.8
        let snow = try XCTUnwrap(store.savePreset(named: "Snow Choice"))
        store.settings.opacity = 0.1
        store.mode = .rain
        XCTAssertEqual(store.selectedPresetID, rain.id)
        XCTAssertEqual(store.settings, rain.settings)
        store.mode = .snow
        XCTAssertEqual(store.selectedPresetID, snow.id)
        XCTAssertEqual(store.settings, snow.settings)

        store.settings.opacity = 0.3
        let restored = RainSettingsStore(userDefaults: defaults)
        XCTAssertEqual(restored.selectedPresetID, snow.id)
        XCTAssertEqual(restored.settings, snow.settings)
        restored.deletePreset(id: snow.id)
        XCTAssertEqual(restored.selectedPresetID, RainPreset.defaultID)
        XCTAssertEqual(RainSettingsStore(userDefaults: defaults).settings, .defaults(for: .snow))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "RainBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
