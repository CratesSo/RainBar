import AppKit
import Combine

@MainActor
final class RainController: ObservableObject {
    @Published private(set) var isRunning = false

    private let settingsStore: RainSettingsStore
    private let tracker = ActiveWindowTracker()
    private var overlayWindow: RainOverlayWindow?
    private var trackingTimer: Timer?
    private var lastTargetUpdate: TimeInterval = 0
    private var wasDraggingWindow = false
    private var settingsCancellable: AnyCancellable?
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

    }

    func start() {
        tracker.requestAccessibilityIfNeeded()
        let frame = currentTargetFrame()

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
                let isDragging = !self.settingsStore.isFullscreen && NSEvent.pressedMouseButtons & 1 != 0
                defer { self.wasDraggingWindow = isDragging }
                // Track the drag and its final position promptly; keep idle AX queries at 4 Hz.
                guard isDragging || self.wasDraggingWindow
                    || ProcessInfo.processInfo.systemUptime - self.lastTargetUpdate >= 0.25 else {
                    return
                }
                self.updateOverlayTarget()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func updateOverlayTarget(isFullscreen: Bool? = nil) {
        lastTargetUpdate = ProcessInfo.processInfo.systemUptime
        guard let frame = currentTargetFrame(isFullscreen: isFullscreen) else {
            // Spaces transitions can temporarily leave no target. Keep tracking so the effect resumes.
            overlayWindow?.hide()
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
        if !overlayWindow.isVisible {
            overlayWindow.show()
        }
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
            ?? tracker.topmostVisibleWindowFrame(excludingProcessIdentifier: NSRunningApplication.current.processIdentifier)
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
        overlayWindow?.show()
    }
}
