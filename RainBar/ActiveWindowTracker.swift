import AppKit
@preconcurrency import ApplicationServices
import Darwin

@MainActor
struct ActiveWindowTracker {
    private static var hasRequestedAccessibility = false
    private static var displayIdentifiers: [UInt32: CFString] = [:]
    private static var screenMaxY = NSScreen.screens.lazy.map(\.frame.maxY).max()
    private var foregroundBundleIdentifier: String?
    private var applicationElement: AXUIElement?
    private typealias WindowIDQuery = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private typealias ScreenRectQuery = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<CGRect>) -> Int32
    private typealias ConnectionQuery = @convention(c) () -> Int32
    private typealias CurrentSpaceQuery = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpaceTransformQuery = @convention(c) (Int32, UInt64, UnsafeMutablePointer<UInt32>?) -> CGAffineTransform
    private typealias MoveWindowsQuery = @convention(c) (Int32, CFArray, UInt64) -> Void

    private static let symbolHandle = dlopen(nil, RTLD_LAZY)
    private static let windowIDQuery: WindowIDQuery? = {
        guard let symbol = dlsym(symbolHandle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDQuery.self)
    }()
    private static let screenRectQuery: ScreenRectQuery? = {
        guard let symbol = dlsym(symbolHandle, "SLSGetScreenRectForWindow") else { return nil }
        return unsafeBitCast(symbol, to: ScreenRectQuery.self)
    }()
    private static let currentSpaceQuery: CurrentSpaceQuery? = {
        guard let symbol = dlsym(symbolHandle, "SLSManagedDisplayGetCurrentSpace") else { return nil }
        return unsafeBitCast(symbol, to: CurrentSpaceQuery.self)
    }()
    private static let spaceTransformQuery: SpaceTransformQuery? = {
        guard let symbol = dlsym(symbolHandle, "SLSSpaceGetTransform") else { return nil }
        return unsafeBitCast(symbol, to: SpaceTransformQuery.self)
    }()
    private static let moveWindowsQuery: MoveWindowsQuery? = {
        guard let symbol = dlsym(symbolHandle, "SLSMoveWindowsToManagedSpace") else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsQuery.self)
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

    static var canPlaceOverlayInSpace: Bool {
        moveWindowsQuery != nil && currentSpaceQuery != nil && connectionID != nil
    }

    static func invalidateScreenParameters() {
        displayIdentifiers.removeAll(keepingCapacity: true)
        screenMaxY = NSScreen.screens.lazy.map(\.frame.maxY).max()
    }

    func displayID(on screen: NSScreen?) -> UInt32? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func currentSpace(on screen: NSScreen?) -> UInt64? {
        guard let currentSpace = Self.currentSpaceQuery, let connectionID = Self.connectionID,
              let displayID = displayID(on: screen) else { return nil }
        let identifier: CFString
        if let cachedIdentifier = Self.displayIdentifiers[displayID] {
            identifier = cachedIdentifier
        } else {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  let createdIdentifier = CFUUIDCreateString(nil, uuid) else { return nil }
            identifier = createdIdentifier
            Self.displayIdentifiers[displayID] = identifier
        }
        let space = currentSpace(connectionID, identifier)
        return space == 0 ? nil : space
    }

    func placeOverlay(_ window: NSWindow, in space: UInt64) {
        guard let move = Self.moveWindowsQuery, let connectionID = Self.connectionID else { return }
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        move(connectionID, windows, space)
    }

    func isSpaceTransitionInProgress(in space: UInt64?) -> Bool {
        guard let transform = Self.spaceTransformQuery, let connectionID = Self.connectionID,
              let space else { return false }
        return !transform(connectionID, space, nil).isIdentity
    }

    mutating func updateForegroundApplication(_ app: NSRunningApplication?) {
        foregroundBundleIdentifier = app?.bundleIdentifier
        applicationElement = app.map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    func focusedWindowFrame(excludingBundleIdentifier excludedBundleIdentifier: String?) -> CGRect? {
        guard foregroundBundleIdentifier != excludedBundleIdentifier,
              let appElement = applicationElement else { return nil }
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
        let screenMaxY = Self.screenMaxY ?? frame.maxY
        return CGRect(
            x: frame.minX,
            y: screenMaxY - frame.minY - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
