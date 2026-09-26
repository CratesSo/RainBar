import AppKit
@preconcurrency import ApplicationServices

struct ActiveWindowTracker {
    @MainActor
    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func focusedWindowFrame(excludingBundleIdentifier excludedBundleIdentifier: String?) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != excludedBundleIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard focusedResult == .success,
              let focusedWindow,
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowElement = focusedWindow as! AXUIElement
        guard let accessibilityFrame = accessibilityFrame(for: windowElement) else {
            return nil
        }

        return convertAccessibilityFrameToAppKitFrame(accessibilityFrame)
    }

    func topmostVisibleWindowFrame(excludingProcessIdentifier excludedProcessIdentifier: pid_t) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowInfo {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != excludedProcessIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }

            let frame = CGRect(
                x: boundsDictionary["X"] ?? 0,
                y: boundsDictionary["Y"] ?? 0,
                width: boundsDictionary["Width"] ?? 0,
                height: boundsDictionary["Height"] ?? 0
            )

            guard frame.width > 80, frame.height > 80 else {
                continue
            }

            return convertAccessibilityFrameToAppKitFrame(frame)
        }

        return nil
    }

    private func accessibilityFrame(for windowElement: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func convertAccessibilityFrameToAppKitFrame(_ frame: CGRect) -> CGRect {
        let screenMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        return CGRect(
            x: frame.minX,
            y: screenMaxY - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
