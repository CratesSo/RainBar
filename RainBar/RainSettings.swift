import Combine
import Foundation

enum WeatherMode: String, Codable {
    case rain, snow
}

enum SnowShape: String, Codable {
    case square, round
}

struct RainColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

struct RainSettings: Codable, Equatable {
    var opacity: Double
    var splashOpacity: Double
    var rainAmount: Double
    var speed: Double
    var trailLength: Double
    var trailLengthVariation: Double
    var trailThickness: Double
    var rainColor: RainColor
    var angle: Double
    var snowFade: Double = 0.5
    var snowSize: Double = 1.0
    var snowShape: SnowShape = .square
    var snowflakeSize: Double = 1.0
    var snowflakeAmount: Double = 1.0 / 23.0
    var snowflakesEnabled: Bool = true
    var splashesEnabled: Bool = true

    static let defaults = RainSettings(
        opacity: 0.09947144905738735,
        splashOpacity: 0.4437146347736625,
        rainAmount: 0.05298026424313051,
        speed: 1.993815104166667,
        trailLength: 28.02502600080627,
        trailLengthVariation: 0.5424405742543583,
        trailThickness: 3.3,
        rainColor: RainColor(
            red: 0.3080240885416666,
            green: 0.7840954065322876,
            blue: 1.0
        ),
        angle: -11.3339309305462
    )

    static func defaults(for mode: WeatherMode) -> RainSettings {
        var settings = defaults
        if mode == .snow {
            settings.rainAmount = 0.05
            settings.opacity = 0.6
            settings.speed = 1.35
            settings.angle = -10
        }
        return settings
    }
}

extension RainSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try values.decode(Double.self, forKey: .opacity)
        splashOpacity = try values.decode(Double.self, forKey: .splashOpacity)
        rainAmount = try values.decode(Double.self, forKey: .rainAmount)
        speed = try values.decode(Double.self, forKey: .speed)
        trailLength = try values.decode(Double.self, forKey: .trailLength)
        trailLengthVariation = try values.decode(Double.self, forKey: .trailLengthVariation)
        trailThickness = try values.decode(Double.self, forKey: .trailThickness)
        rainColor = try values.decode(RainColor.self, forKey: .rainColor)
        angle = try values.decode(Double.self, forKey: .angle)
        snowFade = try values.decodeIfPresent(Double.self, forKey: .snowFade) ?? 0.5
        snowSize = try values.decodeIfPresent(Double.self, forKey: .snowSize) ?? 1.0
        snowShape = try values.decodeIfPresent(SnowShape.self, forKey: .snowShape) ?? .square
        snowflakeSize = try values.decodeIfPresent(Double.self, forKey: .snowflakeSize) ?? snowSize
        snowflakeAmount = try values.decodeIfPresent(Double.self, forKey: .snowflakeAmount) ?? 1.0 / 23.0
        snowflakesEnabled = try values.decodeIfPresent(Bool.self, forKey: .snowflakesEnabled) ?? true
        splashesEnabled = try values.decodeIfPresent(Bool.self, forKey: .splashesEnabled) ?? true
    }
}

struct RainPreset: Codable, Equatable, Identifiable {
    static let defaultID = "default"
    static let defaultName = "Default"

    var id: String
    var name: String
    var settings: RainSettings
    var mode: WeatherMode

    var isDefault: Bool { id == Self.defaultID }

    static func validatedName(_ name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              trimmedName.caseInsensitiveCompare(defaultName) != .orderedSame else {
            return nil
        }
        return trimmedName
    }

    static func defaultPreset(for mode: WeatherMode = .rain) -> RainPreset {
        RainPreset(
            id: defaultID,
            name: defaultName,
            settings: .defaults(for: mode),
            mode: mode
        )
    }
}

@MainActor
final class RainSettingsStore: ObservableObject {
    @Published var mode: WeatherMode {
        didSet {
            guard mode != oldValue else { return }
            userDefaults.set(mode.rawValue, forKey: "weather.mode")
            restoreSelectedPreset()
        }
    }
    @Published var isFullscreen: Bool {
        didSet { userDefaults.set(isFullscreen, forKey: Keys.isFullscreen) }
    }
    @Published private(set) var selectedPresetID = RainPreset.defaultID
    @Published var settings: RainSettings
    @Published private(set) var customPresets: [RainPreset] = []

    var presets: [RainPreset] {
        [RainPreset.defaultPreset(for: mode)] + customPresets.filter { $0.mode == mode }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let initialMode = WeatherMode(rawValue: userDefaults.string(forKey: "weather.mode") ?? "") ?? .rain
        mode = initialMode

        isFullscreen = userDefaults.bool(forKey: Keys.isFullscreen)
        settings = RainSettings.defaults(for: initialMode)
        userDefaults.removeObject(forKey: "rain.customPresets")
        customPresets = loadCustomPresets()
        restoreSelectedPreset()
    }

    private func restoreSelectedPreset() {
        let savedID = userDefaults.string(forKey: "weather.selectedPreset.\(mode.rawValue)")
        let preset = presets.first { $0.id == savedID } ?? .defaultPreset(for: mode)
        loadPreset(preset)
    }

    @discardableResult
    func savePreset(named name: String) -> RainPreset? {
        guard let trimmedName = RainPreset.validatedName(name) else {
            return nil
        }

        if let index = customPresets.firstIndex(where: { $0.mode == mode && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            updatePreset(id: customPresets[index].id)
            return customPresets[index]
        }

        let preset = RainPreset(
            id: UUID().uuidString,
            name: trimmedName,
            settings: settings,
            mode: mode
        )
        customPresets.append(preset)
        saveCustomPresets()
        loadPreset(preset)
        return preset
    }

    func loadPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else {
            return
        }

        loadPreset(preset)
    }

    private func loadPreset(_ preset: RainPreset) {
        settings = preset.settings
        selectedPresetID = preset.id
        userDefaults.set(preset.id, forKey: "weather.selectedPreset.\(mode.rawValue)")
    }

    func updatePreset(id: String) {
        guard id != RainPreset.defaultID,
              let index = customPresets.firstIndex(where: { $0.id == id && $0.mode == mode }) else {
            return
        }

        customPresets[index].settings = settings
        saveCustomPresets()
        loadPreset(customPresets[index])
    }

    func deletePreset(id: String) {
        guard id != RainPreset.defaultID else {
            return
        }

        customPresets.removeAll { $0.id == id && $0.mode == mode }
        saveCustomPresets()
        if selectedPresetID == id { loadPreset(id: RainPreset.defaultID) }
    }

    private func loadCustomPresets() -> [RainPreset] {
        guard let data = userDefaults.data(forKey: Keys.customPresets),
              let presets = try? JSONDecoder().decode([RainPreset].self, from: data) else {
            return []
        }

        return presets.filter { !$0.isDefault }
    }

    private func saveCustomPresets() {
        guard let data = try? JSONEncoder().encode(customPresets) else {
            return
        }

        userDefaults.set(data, forKey: Keys.customPresets)
    }

    private enum Keys {
        static let isFullscreen = "rain.isFullscreen"
        static let customPresets = "weather.customPresets"
    }
}
