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
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RainBar: \(label)")
                image?.isTemplate = true
                self?.statusItem?.button?.image = image
            }
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

    func setControlsHeight(_ height: CGFloat) {
        guard controlsHeight != height else { return }
        controlsHeight = height
        if isExpanded {
            animate(to: height, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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
        guard animated, abs(target - start) > 0.5 else {
            setVisibleHeight(target)
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
                self.setVisibleHeight(start + (target - start) * eased)
                if progress == 1 {
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setVisibleHeight(_ height: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleControlsHeight = height
            onHeightChange(self.height)
        }
    }
}
