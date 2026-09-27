import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let popoverWidth: CGFloat = 368
    private var statusItem: NSStatusItem?
    private var statusIconCancellable: AnyCancellable?
    private let popover = NSPopover()
    private let settingsStore = RainSettingsStore()
    private lazy var menuLayout = MenuLayout { [weak self] height in
        self?.updatePopoverHeight(height)
    }
    private lazy var rainController = RainController(settingsStore: settingsStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = MenuBarView(
            controller: rainController,
            settingsStore: settingsStore,
            layout: menuLayout
        )

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: popoverWidth, height: 430)
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "RainBar"
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        statusIconCancellable = rainController.$isRunning
            .combineLatest(settingsStore.$mode)
            .sink { [weak self] isRunning, mode in
                let symbol = isRunning ? (mode == .rain ? "cloud.rain" : "snowflake") : "cloud"
                let label = isRunning ? (mode == .rain ? "Rain" : "Snow") : "Off"
                self?.statusItem?.button?.image = Self.statusImage(symbol: symbol, label: label)
            }
    }

    static func statusImage(symbol: String, label: String) -> NSImage? {
        guard let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let drawingSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        // The popover anchors to this button; symbol changes must not resize it.
        let image = NSImage(size: size, flipped: false) { bounds in
            source.draw(in: NSRect(
                x: bounds.midX - drawingSize.width / 2,
                y: bounds.midY - drawingSize.height / 2,
                width: drawingSize.width,
                height: drawingSize.height
            ))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "RainBar: \(label)"
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        rainController.stop()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            syncPopoverSize()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverHeight(_ height: CGFloat) {
        let nextHeight = max(1, ceil(height))
        guard nextHeight != popover.contentSize.height else { return }
        popover.contentSize = NSSize(width: popoverWidth, height: nextHeight)
    }

    private func syncPopoverSize() {
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        popover.contentSize = NSSize(width: popoverWidth, height: menuLayout.height)
    }

}

@MainActor
final class MenuLayout: ObservableObject {
    @Published private(set) var visibleControlsHeight: CGFloat = 0
    @Published private(set) var gearRotation: Double = 90
    private var targetGearRotation: Double = 90
    private var headerHeight: CGFloat = 64
    private var controlsHeight: CGFloat = 0
    private var isExpanded = false
    private var timer: Timer?
    private let onHeightChange: (CGFloat) -> Void

    var height: CGFloat { headerHeight + visibleControlsHeight }

    init(onHeightChange: @escaping (CGFloat) -> Void) {
        self.onHeightChange = onHeightChange
    }

    func setHeaderHeight(_ height: CGFloat) {
        guard headerHeight != height else { return }
        headerHeight = height
        onHeightChange(self.height)
    }

    func setControlsHeight(_ height: CGFloat, settingsExpanded: Bool) {
        let rotation = settingsExpanded ? 90.0 : 0.0
        guard controlsHeight != height || targetGearRotation != rotation else { return }
        controlsHeight = height
        targetGearRotation = rotation
        if isExpanded {
            animate(to: height, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else {
            gearRotation = rotation
        }
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        animate(to: expanded ? controlsHeight : 0, animated: animated)
    }

    private func animate(to target: CGFloat, animated: Bool) {
        timer?.invalidate()
        timer = nil
        let start = visibleControlsHeight
        let startRotation = gearRotation
        let targetRotation = targetGearRotation
        guard animated, abs(target - start) > 0.5 || abs(targetRotation - startRotation) > 0.5 else {
            setVisibleHeight(target, rotation: targetRotation)
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / 0.3)
                let eased = progress * progress * (3 - 2 * progress)
                self.setVisibleHeight(
                    start + (target - start) * eased,
                    rotation: startRotation + (targetRotation - startRotation) * eased
                )
                if progress == 1 {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setVisibleHeight(_ height: CGFloat, rotation: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleControlsHeight = height
            gearRotation = rotation
            onHeightChange(self.height)
        }
    }
}
