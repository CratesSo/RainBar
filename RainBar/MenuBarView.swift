import AppKit
import SwiftUI

struct MenuBarView: View {
    private static let toolbarHeight: CGFloat = 32

    @ObservedObject var controller: RainController
    @ObservedObject var settingsStore: RainSettingsStore
    @ObservedObject var layout: MenuLayout
    @State private var isPresetModified = false
    @State private var presetName = ""
    @State private var isShowingPresetPopover = false
    @State private var isShowingPresetPicker = false
    @State private var hoveredPresetID: String?
    @State private var areSettingsExpanded = true
    @State private var fullControlsHeight: CGFloat = 0
    @State private var presetControlsHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sourcePresetID: String? {
        let id = settingsStore.selectedPresetID
        return id == RainPreset.defaultID ? nil : id
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        settingsStore.isFullscreen.toggle()
                    } label: {
                        FullscreenArrows(separation: settingsStore.isFullscreen ? 3 : 0)
                        .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .butt, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: settingsStore.isFullscreen)
                        .frame(width: Self.toolbarHeight, height: Self.toolbarHeight)
                        .background(.primary.opacity(settingsStore.isFullscreen ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 9))
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fullscreen")
                    .accessibilityValue(settingsStore.isFullscreen ? "On" : "Off")
                    .help("Fullscreen")
                    .rainInteraction(cornerRadius: 9)

                    HStack(spacing: 4) {
                        modeButton(.rain, title: "Rain", symbol: "cloud.rain")
                        modeButton(.snow, title: "Snow", symbol: "snowflake")
                        modeButton(nil, title: "Off", symbol: "cloud")
                    }
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .frame(width: Self.toolbarHeight, height: Self.toolbarHeight)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quit")
                    .help("Quit RainBar")
                    .rainInteraction()
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    layout.setHeaderHeight(height + 32)
                }

                VStack(alignment: .leading, spacing: 16) {
                    presetControls
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            presetControlsHeight = height
                            updateControlsHeight()
                        }

                    VStack(alignment: .leading, spacing: 16) {
                        Divider()

                        HStack(spacing: 16) {
                            sliderControl(
                                title: settingsStore.mode == .snow ? "Snow Amount" : "Rain Amount",
                                valueText: "\(Int((settingsStore.settings.rainAmount * 100).rounded()))%",
                                value: $settingsStore.settings.rainAmount,
                                range: 0.0...1.0
                            )

                            if settingsStore.mode == .snow {
                                sliderControl(
                                    title: "Snow Size",
                                    valueText: String(format: "%.2f×", settingsStore.settings.snowSize),
                                    value: $settingsStore.settings.snowSize,
                                    range: 0.25...3.0
                                )
                            } else {
                                sliderControl(
                                    title: "Rain Size",
                                    valueText: String(format: "%.1f pt", settingsStore.settings.trailThickness),
                                    value: $settingsStore.settings.trailThickness,
                                    range: 1.6...3.3
                                )
                            }
                        }

                        Divider()

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            sliderControl(
                                title: settingsStore.mode == .snow ? "Snow Opacity" : "Rain Opacity",
                                valueText: String(format: "%.0f%%", settingsStore.settings.opacity * 100),
                                value: $settingsStore.settings.opacity,
                                range: settingsStore.mode == .snow ? 0.0...1.0 : 0.05...0.5
                            )

                            if settingsStore.mode == .snow {
                                sliderControl(
                                    title: "Snow Fade",
                                    valueText: String(format: "%.0f%%", settingsStore.settings.snowFade * 100),
                                    value: $settingsStore.settings.snowFade,
                                    range: 0.0...1.0
                                )
                            }

                            if settingsStore.mode == .rain {
                                sliderControl(
                                    title: "Splash Opacity",
                                    valueText: String(format: "%.0f%%", settingsStore.settings.splashOpacity * 100),
                                    value: $settingsStore.settings.splashOpacity,
                                    range: 0.0...1.0
                                )
                            }
                        }

                        Divider()

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            sliderControl(
                                title: "Speed",
                                valueText: String(format: "%.2f×", settingsStore.settings.speed),
                                value: $settingsStore.settings.speed,
                                range: 0.25...(settingsStore.mode == .rain ? 4.0 : 3.0)
                            )

                            sliderControl(
                                title: "Angle",
                                valueText: "\(Int(settingsStore.settings.angle.rounded())) deg",
                                value: $settingsStore.settings.angle,
                                range: -45.0...45.0
                            )
                        }

                        if settingsStore.mode == .snow {
                            Divider()

                            HStack(spacing: 16) {
                                sliderControl(
                                    title: "Snowflake Size",
                                    valueText: String(format: "%.2f×", settingsStore.settings.snowflakeSize),
                                    value: $settingsStore.settings.snowflakeSize,
                                    range: 0.25...3.0
                                )

                                sliderControl(
                                    title: "Snowflake Amount",
                                    valueText: String(format: "%.0f%%", settingsStore.settings.snowflakeAmount * 100),
                                    value: $settingsStore.settings.snowflakeAmount,
                                    range: 0.0...1.0
                                )
                            }
                        }

                        if settingsStore.mode == .rain {
                            Divider()

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)
                                ],
                                alignment: .leading,
                                spacing: 16
                            ) {

                                sliderControl(
                                    title: "Trail Length",
                                    valueText: String(format: "%.1f pt", settingsStore.settings.trailLength),
                                    value: $settingsStore.settings.trailLength,
                                    range: 6.0...48.0
                                )

                                sliderControl(
                                    title: "Trail Variation",
                                    valueText: "\(Int((settingsStore.settings.trailLengthVariation * 100).rounded()))%",
                                    value: $settingsStore.settings.trailLengthVariation,
                                    range: 0.0...1.0
                                )
                            }

                            Divider()

                            HStack(spacing: 16) {
                                RainColorPicker(
                                    rainColor: $settingsStore.settings.rainColor
                                )

                                Toggle("Splashes", isOn: $settingsStore.settings.splashesEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .fixedSize()
                            }
                        }

                        if settingsStore.mode == .snow {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Snow Shape")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Picker("Snow Shape", selection: $settingsStore.settings.snowShape) {
                                        Text("Square").tag(SnowShape.square)
                                        Text("Round").tag(SnowShape.round)
                                    }
                                    .pickerStyle(.radioGroup)
                                    .horizontalRadioGroupLayout()
                                    .labelsHidden()

                                    Spacer()

                                    Toggle("Snowflakes", isOn: $settingsStore.settings.snowflakesEnabled)
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                        .fixedSize()
                                }
                            }
                        }
                    }
                    .allowsHitTesting(areSettingsExpanded)
                    .accessibilityHidden(!areSettingsExpanded)
                }
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    fullControlsHeight = height
                    updateControlsHeight()
                }
                .frame(height: layout.visibleControlsHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(controller.isRunning)
                .accessibilityHidden(!controller.isRunning)
            }
            .padding(16)
            .frame(width: 368)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: controller.isRunning, initial: true) { _, running in
                layout.setExpanded(running, animated: !reduceMotion)
                if !running { isShowingPresetPicker = false }
            }
            .onChange(of: areSettingsExpanded) { _, _ in
                updateControlsHeight()
            }
            .onChange(of: settingsStore.settings) { _, settings in
                updatePresetModificationState(settings)
            }
            .onChange(of: settingsStore.mode) { _, _ in
                isShowingPresetPicker = false
                isPresetModified = false
                isShowingPresetPopover = false
            }
        }

    private func updateControlsHeight() {
        layout.setControlsHeight(
            areSettingsExpanded ? fullControlsHeight : presetControlsHeight + 16,
            settingsExpanded: areSettingsExpanded
        )
    }

    private func modeButton(_ mode: WeatherMode?, title: String, symbol: String) -> some View {
        let isSelected = controller.isRunning ? mode == settingsStore.mode : mode == nil

        return Button {
            if let mode {
                settingsStore.mode = mode
                controller.start()
            } else {
                controller.stop()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.toolbarHeight)
            .background(.primary.opacity(isSelected ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rainInteraction(cornerRadius: 9)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var presetControls: some View {
        let canOverwritePreset = isPresetModified && sourcePresetID != nil
        let selectedPresetName = isPresetModified ? "Modified"
            : settingsStore.presets.first { $0.id == settingsStore.selectedPresetID }?.name ?? "Modified"

        return VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    areSettingsExpanded.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .rotationEffect(.degrees(layout.gearRotation))
                        .frame(width: 32, height: 32)
                        .background(.primary.opacity(areSettingsExpanded ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .rainInteraction(cornerRadius: 9)
                .help(areSettingsExpanded ? "Hide settings" : "Show settings")
                .accessibilityLabel("Settings")
                .accessibilityValue(areSettingsExpanded ? "Expanded" : "Collapsed")

                Button {
                    isShowingPresetPicker.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Label(selectedPresetName,
                              systemImage: settingsStore.mode == .rain ? "cloud.rain" : "snowflake")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .rainInteraction(cornerRadius: 9)
                .accessibilityLabel("Preset")
                .accessibilityValue(selectedPresetName)
                .popover(isPresented: $isShowingPresetPicker, arrowEdge: .bottom) {
                    presetPickerPopover
                }

                Button {
                    presetName = ""
                    isShowingPresetPopover = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 12, height: 20)
                }
                .rainInteraction()
                .frame(height: 32)
                .help("New preset")
                .popover(isPresented: $isShowingPresetPopover, arrowEdge: .bottom) {
                    newPresetPopover
                }

                Button {
                    guard let sourcePresetID else {
                        return
                    }

                    settingsStore.updatePreset(id: sourcePresetID)
                    isPresetModified = false
                } label: {
                    Path { path in
                        path.move(to: CGPoint(x: 1, y: 1))
                        path.addLine(to: CGPoint(x: 10, y: 1))
                        path.addLine(to: CGPoint(x: 13, y: 4))
                        path.addLine(to: CGPoint(x: 13, y: 13))
                        path.addLine(to: CGPoint(x: 1, y: 13))
                        path.closeSubpath()
                        path.addRect(CGRect(x: 4, y: 1, width: 5, height: 4))
                        path.addRect(CGRect(x: 3, y: 8, width: 8, height: 5))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    .frame(width: 14, height: 14)
                    .frame(height: 20)
                }
                .rainInteraction()
                .frame(height: 32)
                .disabled(!canOverwritePreset)
                .accessibilityLabel("Save current preset")
                .help("Save current preset")


            }
        }
    }

    private var presetPickerPopover: some View {
        let rowCount = settingsStore.presets.count + (isPresetModified ? 1 : 0)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(settingsStore.presets) { preset in
                    HStack(spacing: 6) {
                        Button {
                            settingsStore.loadPreset(id: preset.id)
                            isPresetModified = false
                            isShowingPresetPicker = false
                            presetName = ""
                        } label: {
                            Label(preset.name, systemImage: preset.mode == .rain ? "cloud.rain" : "snowflake")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .rainInteraction(cornerRadius: 12)
                        .accessibilityAddTraits(!isPresetModified && settingsStore.selectedPresetID == preset.id ? .isSelected : [])

                        if !preset.isDefault {
                            Button {
                                let wasSelected = settingsStore.selectedPresetID == preset.id
                                settingsStore.deletePreset(id: preset.id)
                                if wasSelected {
                                    isPresetModified = false
                                }
                                hoveredPresetID = nil
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .rainInteraction(cornerRadius: 12)
                            .help("Delete \(preset.name)")
                            .accessibilityLabel("Delete \(preset.name)")
                            .opacity(hoveredPresetID == preset.id ? 1 : 0)
                            .allowsHitTesting(hoveredPresetID == preset.id)
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovered in
                        if hovered { hoveredPresetID = preset.id }
                        else if hoveredPresetID == preset.id { hoveredPresetID = nil }
                    }
                }

                if isPresetModified {
                    Label("Modified", systemImage: settingsStore.mode == .rain ? "cloud.rain" : "snowflake")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .padding(8)
        }
        .frame(width: 280, height: CGFloat(min(rowCount, 8)) * 32 + 16)
        .onExitCommand { isShowingPresetPicker = false }
        .onDisappear { hoveredPresetID = nil }
    }

    private var newPresetPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Preset")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(saveNewPreset)

                Button("Cancel") {
                    isShowingPresetPopover = false
                }
                .rainInteraction()

                Button("Save", action: saveNewPreset)
                    .rainInteraction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(RainPreset.validatedName(presetName) == nil)
            }
        }
        .padding(16)
    }

    private func saveNewPreset() {
        guard settingsStore.savePreset(named: presetName) != nil else {
            return
        }

        isPresetModified = false
        isShowingPresetPopover = false
    }

    private func updatePresetModificationState(_ settings: RainSettings) {
        guard !isPresetModified else { return }

        let selectedPreset = settingsStore.presets.first { $0.id == settingsStore.selectedPresetID }
        if selectedPreset?.settings != settings {
            isPresetModified = true
        }
    }

    private func sliderControl(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
                .controlSize(.regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct FullscreenArrows: Shape {
    var separation: CGFloat

    var animatableData: CGFloat {
        get { separation }
        set { separation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let reach = 7 + separation
        let start = CGPoint(x: rect.midX - reach, y: rect.midY - reach)
        let end = CGPoint(x: rect.midX + reach, y: rect.midY + reach)

        return Path { path in
            path.move(to: start)
            if separation > 0 {
                path.addLine(to: CGPoint(x: rect.midX - separation, y: rect.midY - separation))
                path.move(to: CGPoint(x: rect.midX + separation, y: rect.midY + separation))
            }
            path.addLine(to: end)

            path.move(to: CGPoint(x: start.x, y: start.y + 5))
            path.addLine(to: start)
            path.addLine(to: CGPoint(x: start.x + 5, y: start.y))
            path.move(to: CGPoint(x: end.x - 5, y: end.y))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x, y: end.y - 5))
        }
    }
}

private struct RainColorPicker: View {
    @Binding var rainColor: RainColor
    @State private var hexText: String
    @State private var isPickerPresented = false

    init(rainColor: Binding<RainColor>) {
        _rainColor = rainColor
        _hexText = State(initialValue: Self.hexString(from: rainColor.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPickerPresented.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: rainColor.red, green: rainColor.green, blue: rainColor.blue))
                        .frame(width: 28, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.secondary.opacity(0.35), lineWidth: 1)
                        )

                    Text(hexText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rainInteraction(highlight: false)
            .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                RainThemeColorPicker(rainColor: $rainColor)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Spacer()

                    TextField("Hex", text: Binding(
                        get: { hexText },
                        set: { newValue in
                            hexText = newValue.uppercased()
                            if let parsedColor = Self.rainColor(fromHex: newValue) {
                                rainColor = parsedColor
                            }
                        }
                    ))
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)
                    Spacer()
                }

                }
                .padding(12)
                .fixedSize()
            }
        }
        .onChange(of: rainColor) { _, color in
            let newHexText = Self.hexString(from: color)
            if hexText != newHexText {
                hexText = newHexText
            }
        }
    }

    private static func hexString(from rainColor: RainColor) -> String {
        let red = Int(max(0, min(255, (rainColor.red * 255).rounded())))
        let green = Int(max(0, min(255, (rainColor.green * 255).rounded())))
        let blue = Int(max(0, min(255, (rainColor.blue * 255).rounded())))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func rainColor(fromHex hex: String) -> RainColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }

        return RainColor(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}


private struct RainInteraction: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let highlight: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(isHovered && isEnabled ? 0.08 : 0))
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                updateHover(hovering && isEnabled)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { updateHover(false) }
            }
            .onDisappear { updateHover(false) }
    }

    private func updateHover(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        if hovered { NSCursor.pointingHand.push() }
        else { NSCursor.pop() }
    }
}

private extension View {
    func rainInteraction(highlight: Bool = true, cornerRadius: CGFloat = 6) -> some View {
        modifier(RainInteraction(highlight: highlight, cornerRadius: cornerRadius))
    }
}


private struct RainThemeColorPicker: View {
    @Binding var rainColor: RainColor
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 0
    @State private var brightness: CGFloat = 1

    private let scale: CGFloat = 0.6

    private var width: CGFloat { 320 * scale }
    private var squareHeight: CGFloat { 280 * scale }
    private var hueHeight: CGFloat { 42 * scale }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [.white, Color(hue: Double(hue), saturation: 1, brightness: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(Color(nsColor: selectedColor))
                        .frame(width: 42 * scale, height: 42 * scale)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .shadow(color: .black.opacity(0.45), radius: 2 * scale)
                        .position(
                            x: saturation * geometry.size.width,
                            y: (1 - brightness) * geometry.size.height
                        )
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, value.location.x / geometry.size.width))
                    brightness = 1 - min(1, max(0, value.location.y / geometry.size.height))
                    writeColor()
                })
            }
            .frame(height: squareHeight)

            Rectangle()
                .fill(.black)
                .frame(height: 1)

            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, Color(nsColor: .magenta), .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    Circle()
                        .fill(Color(hue: Double(hue), saturation: 1, brightness: 1))
                        .frame(width: 38 * scale, height: 38 * scale)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5 * scale))
                        .shadow(color: .black.opacity(0.45), radius: 2 * scale)
                        .position(x: hue * geometry.size.width, y: geometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    hue = min(1, max(0, value.location.x / geometry.size.width))
                    writeColor()
                })
            }
            .frame(height: hueHeight)
            .rainInteraction(highlight: false)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 13 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 13 * scale)
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .padding(5 * scale)
        .background(Color(nsColor: NSColor(white: 0.11, alpha: 1)), in: RoundedRectangle(cornerRadius: 18 * scale))
        .preferredColorScheme(.dark)
        .onAppear(perform: readColor)
        .onChange(of: rainColor) { _, _ in readColor() }
    }

    private var selectedColor: NSColor {
        NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private func readColor() {
        let color = NSColor(srgbRed: rainColor.red, green: rainColor.green, blue: rainColor.blue, alpha: 1)
        if color.saturationComponent > 0 { hue = color.hueComponent }
        saturation = color.saturationComponent
        brightness = color.brightnessComponent
    }

    private func writeColor() {
        let color = selectedColor.usingColorSpace(.sRGB) ?? selectedColor
        rainColor = RainColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
}
