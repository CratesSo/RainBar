import AppKit
import Combine

@MainActor
final class RainController: ObservableObject {
    @Published private(set) var isRunning = false

    private let settingsStore: RainSettingsStore
    private var tracker = ActiveWindowTracker()
    private let processIdentifier = ProcessInfo.processInfo.processIdentifier
    private var overlayWindow: RainOverlayWindow?
    private var overlaySpace: UInt64?
    private var trackingTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var screenParametersCancellable: AnyCancellable?
    private var foregroundApplicationObservation: NSKeyValueObservation?
    private var lastFullscreenSetting: Bool

    init(settingsStore: RainSettingsStore) {
        self.settingsStore = settingsStore
        lastFullscreenSetting = settingsStore.isFullscreen

        settingsCancellable = settingsStore.$settings.combineLatest(settingsStore.$mode, settingsStore.$isFullscreen).sink { [weak self] settings, mode, isFullscreen in
            guard let self else {
                return
            }

            let fullscreenChanged = isFullscreen != lastFullscreenSetting
            lastFullscreenSetting = isFullscreen

            overlayWindow?.apply(settings: settings, mode: mode)
            if isRunning, fullscreenChanged {
                updateOverlayTarget(isFullscreen: isFullscreen)
            }
        }

        foregroundApplicationObservation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.tracker.updateForegroundApplication(NSWorkspace.shared.frontmostApplication)
            }
        }

        screenParametersCancellable = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { _ in
                MainActor.assumeIsolated {
                    ActiveWindowTracker.invalidateScreenParameters()
                }
            }
    }

    func start() {
        tracker.requestAccessibilityIfNeeded()
        let space = tracker.currentSpace(on: overlayWindow?.screen ?? NSScreen.main)
        let frame = tracker.isSpaceTransitionInProgress(in: space) ? nil : currentTargetFrame()

        guard let frame else {
            overlayWindow?.hide()
            return
        }

        showOverlay(frame: frame)
        isRunning = true
        startTrackingTimer()
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        overlayWindow?.hide()
        isRunning = false
    }

    private func startTrackingTimer() {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateOverlayTarget()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func updateOverlayTarget(isFullscreen: Bool? = nil) {
        let trackedScreen = overlayWindow?.screen ?? NSScreen.main
        let trackedDisplayID = tracker.displayID(on: trackedScreen)
        let space = tracker.currentSpace(on: trackedScreen)
        let isSwitchingSpaces = tracker.isSpaceTransitionInProgress(in: space)
        guard !isSwitchingSpaces, let frame = currentTargetFrame(isFullscreen: isFullscreen) else {
            overlayWindow?.hide(animated: isSwitchingSpaces)
            overlayWindow?.updateFade()
            return
        }

        guard let overlayWindow else {
            return
        }

        if overlayWindow.frame.size != frame.size {
            overlayWindow.setFrame(frame, display: true)
        } else if overlayWindow.frame.origin != frame.origin {
            overlayWindow.setFrameOrigin(frame.origin)
        }
        let placementScreen = overlayWindow.screen ?? NSScreen.main
        let placementSpace = tracker.displayID(on: placementScreen) == trackedDisplayID
            ? space
            : tracker.currentSpace(on: placementScreen)
        placeOverlay(in: placementSpace)
        overlayWindow.show()
        overlayWindow.updateFade()
    }

    private func currentTargetFrame(isFullscreen: Bool? = nil) -> CGRect? {
        guard let windowFrame = currentWindowFrame() else {
            return nil
        }

        if isFullscreen ?? settingsStore.isFullscreen {
            return screenFrame(containing: windowFrame)
        }

        return windowFrame
    }

    private func currentWindowFrame() -> CGRect? {
        tracker.focusedWindowFrame(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
            ?? tracker.topmostVisibleWindowFrame(excludingProcessIdentifier: processIdentifier)
    }

    private func screenFrame(containing frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }?.frame
            ?? NSScreen.main?.frame
            ?? frame
    }

    private func showOverlay(frame: CGRect) {
        if overlayWindow == nil {
            overlayWindow = RainOverlayWindow(settings: settingsStore.settings, mode: settingsStore.mode)
        }

        overlayWindow?.setFrame(frame, display: true)
        placeOverlay(in: tracker.currentSpace(on: overlayWindow?.screen ?? NSScreen.main))
        overlayWindow?.show()
    }

    private func placeOverlay(in space: UInt64?) {
        guard ActiveWindowTracker.canPlaceOverlayInSpace, let overlayWindow, let space,
              space != overlaySpace else { return }
        overlayWindow.hide()
        tracker.placeOverlay(overlayWindow, in: space)
        overlaySpace = space
    }
}
