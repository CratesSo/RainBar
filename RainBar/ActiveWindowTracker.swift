import AppKit
@preconcurrency import ApplicationServices
import Darwin

@MainActor
struct ActiveWindowTracker {
    private static var hasRequestedAccessibility = false
    private typealias WindowIDQuery = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private typealias ScreenRectQuery = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    private typealias ConnectionQuery = @convention(c) () -> Int32

    // These private, read-only APIs expose the composited rectangle during Mission Control.
    // Keep the existing AX/CG bounds when the symbols or queries are unavailable.
    private static let symbolHandle = dlopen(nil, RTLD_LAZY)
    private static let windowIDQuery: WindowIDQuery? = {
        guard let symbol = dlsym(symbolHandle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDQuery.self)
    }()
    private static let screenRectQuery: ScreenRectQuery? = {
        guard let symbol = dlsym(symbolHandle, "SLSGetScreenRectForWindow") else { return nil }
        return unsafeBitCast(symbol, to: ScreenRectQuery.self)
    }()
    private static let connectionID: Int32? = {
        guard let symbol = dlsym(symbolHandle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: ConnectionQuery.self)()
    }()

    func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted(), !Self.hasRequestedAccessibility else {
            return
        }

        Self.hasRequestedAccessibility = true
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
        var windowID: CGWindowID = 0
        if let query = Self.windowIDQuery, query(windowElement, &windowID) == 0,
           let frame = compositedFrame(for: windowID) {
            return convertAccessibilityFrameToAppKitFrame(frame)
        }
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
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                continue
            }

            guard frame.width > 80, frame.height > 80 else {
                continue
            }

            let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            let visibleFrame = windowID.flatMap { compositedFrame(for: $0) } ?? frame
            return convertAccessibilityFrameToAppKitFrame(visibleFrame)
        }

        return nil
    }

    private func compositedFrame(for windowID: CGWindowID) -> CGRect? {
        guard let query = Self.screenRectQuery, let connectionID = Self.connectionID else { return nil }
        var frame = CGRect.zero
        guard query(connectionID, windowID, &frame) == 0,
              !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private func accessibilityFrame(for windowElement: AXUIElement) -> CGRect? {
        var attributeValues: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            windowElement,
            [kAXPositionAttribute, kAXSizeAttribute] as CFArray,
            .stopOnError,
            &attributeValues
        ) == .success,
              let values = attributeValues as? [AXValue],
              values.count == 2 else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(values[0], .cgPoint, &position),
              AXValueGetValue(values[1], .cgSize, &size),
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
