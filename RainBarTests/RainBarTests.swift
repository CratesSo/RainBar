import XCTest
@testable import RainBar

@MainActor
final class RainBarTests: XCTestCase {
    func testRainRescalesExistingParticlesImmediatelyOnResize() {
        let view = RainEmitterView(settings: .defaults)
        view.setFrameSize(NSSize(width: 1600, height: 1200))

        for size in [NSSize(width: 400, height: 300), NSSize(width: 1200, height: 800)] {
            let oldSize = view.bounds.size
            let previousParticles = view.particles
            view.setFrameSize(size)

            XCTAssertFalse(view.particles.isEmpty)
            for (particle, previous) in zip(view.particles, previousParticles) {
                XCTAssertEqual(particle.point.x, previous.point.x * size.width / oldSize.width, accuracy: 1e-9)
                XCTAssertEqual(particle.point.y, previous.point.y * size.height / oldSize.height, accuracy: 1e-9)
                XCTAssertEqual(particle.lengthNoise, previous.lengthNoise)
                XCTAssertTrue(view.bounds.contains(particle.point))
            }
        }
    }

    func testSnowPreservesFallPhaseAcrossResizeAndWindChanges() {
        let view = SnowEmitterView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        var settings = RainSettings.defaults(for: .snow)
        view.apply(settings: settings)
        let phases = view.particles.map { $0.age / snowFallTime(height: 300, settings: settings) }

        view.setFrameSize(NSSize(width: 1600, height: 1200))
        settings.angle = 45
        view.apply(settings: settings)
        let duration = snowFallTime(height: 1200, settings: settings)
        for (particle, phase) in zip(view.particles, phases) {
            XCTAssertEqual(particle.age / duration, phase, accuracy: 1e-12)
            XCTAssertEqual(particle.point.y, 1230 - 1260 * phase * phase, accuracy: 1e-9)
        }

        let beforeShrink = view.particles
        view.setFrameSize(NSSize(width: 400, height: 200))
        let smallerDuration = snowFallTime(height: 200, settings: settings)
        for (particle, previous) in zip(view.particles, beforeShrink) {
            let phase = previous.age / duration
            XCTAssertEqual(particle.age / smallerDuration, phase, accuracy: 1e-12)
            XCTAssertEqual(particle.point.x, (previous.point.x + 30) * 460 / 1660 - 30, accuracy: 1e-9)
            XCTAssertEqual(particle.point.y, 230 - 260 * phase * phase, accuracy: 1e-9)
        }
    }

    func testSnowRetainsDistinctPhasesAcrossRepeatedRecycling() {
        let view = SnowEmitterView(frame: NSRect(x: 0, y: 0, width: 800, height: 1200))
        let settings = RainSettings.defaults(for: .snow)
        view.apply(settings: settings)
        let initialAges = view.particles.map(\.age)
        let duration = snowFallTime(height: 1200, settings: settings)
        // Several complete falls, with varying frame intervals.
        let deltas = [1.0 / 60, 1.0 / 120, 1.0 / 20]
        var elapsed = 0.0
        for frame in 0..<3600 {
            let delta = deltas[frame % deltas.count]
            view.advance(by: delta)
            elapsed += delta * settings.speed / RainSettings.defaults.speed
        }
        XCTAssertEqual(view.particles.count, initialAges.count)
        for (particle, initialAge) in zip(view.particles, initialAges) {
            let expectedAge = (initialAge + elapsed).truncatingRemainder(dividingBy: duration)
            XCTAssertEqual(particle.age, expectedAge, accuracy: 1e-8)
            let phase = expectedAge / duration
            XCTAssertEqual(particle.point.y, 1230 - 1260 * phase * phase, accuracy: 1e-6)
        }
    }

    private func snowFallTime(height: Double, settings: RainSettings) -> Double {
        sqrt(2 * (height + 60) / (16.25625 * cos(settings.angle * .pi / 180)))
    }

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
        store.settings.snowSize = 2.0
        store.settings.snowShape = .round
        store.settings.snowflakeSize = 1.5
        store.settings.snowflakeAmount = 0.75
        store.settings.snowflakesEnabled = false
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
        XCTAssertEqual(restoredStore.settings.snowSize, 2.0)
        XCTAssertEqual(restoredStore.settings.snowShape, .round)
        XCTAssertEqual(restoredStore.settings.snowflakeSize, 1.5)
        XCTAssertEqual(restoredStore.settings.snowflakeAmount, 0.75)
        XCTAssertFalse(restoredStore.settings.snowflakesEnabled)
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

    func testSplashTogglePersistsWithoutChangingOpacity() {
        let defaults = makeUserDefaults()
        let store = RainSettingsStore(userDefaults: defaults)
        store.settings.splashOpacity = 0.35
        store.settings.splashesEnabled = false
        store.savePreset(named: "No Splashes")

        let restored = RainSettingsStore(userDefaults: defaults)
        XCTAssertFalse(restored.settings.splashesEnabled)
        XCTAssertEqual(restored.settings.splashOpacity, 0.35)
        restored.settings.splashesEnabled = true
        XCTAssertEqual(restored.settings.splashOpacity, 0.35)
    }

    func testOlderPresetsKeepSplashesEnabled() throws {
        let encoded = try JSONEncoder().encode(RainSettings.defaults)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "splashesEnabled")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let restored = try JSONDecoder().decode(RainSettings.self, from: data)
        XCTAssertEqual(restored, .defaults)
        XCTAssertTrue(restored.splashesEnabled)
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

    func testOlderPresetsPreserveOriginalSnowSize() throws {
        var settings = RainSettings.defaults(for: .snow)
        settings.snowFade = 0.8
        let encoded = try JSONEncoder().encode(settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "snowSize")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let restored = try JSONDecoder().decode(RainSettings.self, from: data)

        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.snowSize, 1.0)
    }

    func testOlderPresetsPreserveOriginalSnowShape() throws {
        var settings = RainSettings.defaults(for: .snow)
        settings.snowSize = 2.0
        let encoded = try JSONEncoder().encode(settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "snowShape")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let restored = try JSONDecoder().decode(RainSettings.self, from: data)

        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.snowShape, .square)
    }

    func testOlderPresetsPreserveSnowflakeSizeAndProportion() throws {
        var settings = RainSettings.defaults(for: .snow)
        settings.snowSize = 2.0
        let encoded = try JSONEncoder().encode(settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "snowflakeSize")
        legacy.removeValue(forKey: "snowflakeAmount")
        legacy.removeValue(forKey: "snowflakesEnabled")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let restored = try JSONDecoder().decode(RainSettings.self, from: data)

        settings.snowflakeSize = settings.snowSize
        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.snowflakeAmount, 1.0 / 23.0)
        XCTAssertTrue(restored.snowflakesEnabled)
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

    func testStatusIconChangesKeepPopoverAnchorStable() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        var initialFrame: NSRect?

        for (symbol, label) in [("cloud", "Off"), ("snowflake", "Snow"), ("cloud.rain", "Rain"), ("cloud", "Off")] {
            let image = try XCTUnwrap(AppDelegate.statusImage(symbol: symbol, label: label))
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.accessibilityDescription, "RainBar: \(label)")
            button.image = image
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            if let initialFrame {
                XCTAssertEqual(button.frame, initialFrame, "\(label) moved the popover anchor")
            } else {
                initialFrame = button.frame
            }
        }
    }

    func testMenuExpansionReversesFromCurrentHeight() {
        var reportedHeight: CGFloat = 0
        let layout = MenuLayout { reportedHeight = $0 }
        layout.setHeaderHeight(70)
        layout.setControlsHeight(400, settingsExpanded: true)
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

    func testGearRotationTracksSettingsExpansionAndReversal() {
        let layout = MenuLayout { _ in }
        layout.setControlsHeight(400, settingsExpanded: true)
        layout.setExpanded(true, animated: false)
        XCTAssertEqual(layout.gearRotation, 90)

        layout.setControlsHeight(80, settingsExpanded: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(layout.gearRotation, 90 * (layout.visibleControlsHeight - 80) / 320, accuracy: 0.001)

        let partialRotation = layout.gearRotation
        layout.setControlsHeight(400, settingsExpanded: true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual(layout.gearRotation, partialRotation)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(layout.gearRotation, 90 * (layout.visibleControlsHeight - 80) / 320, accuracy: 0.001)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertEqual(layout.gearRotation, 90)
        XCTAssertEqual(layout.visibleControlsHeight, 400)

        layout.setControlsHeight(80, settingsExpanded: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        XCTAssertEqual(layout.gearRotation, 0)
        XCTAssertEqual(layout.visibleControlsHeight, 80)
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
