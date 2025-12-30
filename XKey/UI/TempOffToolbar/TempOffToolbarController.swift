//
//  TempOffToolbarController.swift
//  XKey
//
//  Controller for the floating temp off toolbar near cursor
//  Similar to macOS Fn popup behavior
//

import Cocoa
import SwiftUI

class TempOffToolbarController {

    // MARK: - Singleton

    static let shared = TempOffToolbarController()

    // MARK: - Properties

    private var panel: NSPanel?
    private let viewModel = TempOffToolbarViewModel()
    private var hideTimer: Timer?
    private var modifierMonitor: Any?  // Monitor for Ctrl/Option key

    /// Auto-hide delay in seconds (0 = never auto-hide)
    var autoHideDelay: TimeInterval = 0

    /// Callback when temp off states change
    var onStateChange: ((Bool, Bool) -> Void)?  // (spellingTempOff, engineTempOff)

    // MARK: - Initialization

    private init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        viewModel.onSpellingToggle = { [weak self] isOff in
            self?.notifyStateChange()
        }

        viewModel.onEngineToggle = { [weak self] isOff in
            self?.notifyStateChange()
        }
    }

    private func notifyStateChange() {
        onStateChange?(viewModel.isSpellingTempOff, viewModel.isEngineTempOff)
    }

    // MARK: - Panel Management

    private func createPanel() -> NSPanel {
        let toolbarView = TempOffToolbarView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: toolbarView)

        // Create panel with special styling for floating toolbar
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .popUpMenu  // Above most windows
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // We use SwiftUI shadow
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Size to fit content
        if let contentSize = hostingController.view.fittingSize as NSSize? {
            panel.setContentSize(contentSize)
        }

        return panel
    }

    // MARK: - Show/Hide

    /// Show the toolbar at the current cursor position
    func show() {
        // Create panel if needed
        if panel == nil {
            panel = createPanel()
        }

        guard let panel = panel else { return }

        // Always show both buttons when toolbar is enabled
        viewModel.updateVisibility(showSpelling: true, showEngine: true)

        // Resize panel based on visible buttons
        resizePanelForContent()

        // Enable logging for this show
        shouldLogPositioning = true

        // Position near cursor
        positionNearCursor()

        // Disable logging for subsequent updates (timer-based)
        shouldLogPositioning = false

        // Show panel
        panel.orderFront(nil)

        // Setup auto-hide if configured
        setupAutoHide()

        // Setup modifier key monitor (Ctrl/Option toggle)
        setupModifierMonitor()
    }

    /// Hide the toolbar
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        removeModifierMonitor()
        panel?.orderOut(nil)
    }

    /// Toggle toolbar visibility
    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Check if toolbar is visible
    var isVisible: Bool {
        return panel?.isVisible == true
    }

    /// Update toolbar position (call when cursor moves)
    func updatePosition() {
        guard panel?.isVisible == true else { return }
        positionNearCursor()
    }

    // MARK: - Modifier Key Monitor (Ctrl/Option toggle)

    /// Track last modifier state to detect key press (not just holding)
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    private func setupModifierMonitor() {
        // Remove existing monitor
        removeModifierMonitor()

        // Monitor for modifier key changes (Ctrl/Option) - use GLOBAL monitor
        // so it works even when other apps are focused
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierChange(event)
        }
    }

    private func removeModifierMonitor() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        lastModifierFlags = []
    }

    private func handleModifierChange(_ event: NSEvent) {
        guard panel?.isVisible == true else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Check for Ctrl key press (was not pressed, now pressed)
        let ctrlWasPressed = !lastModifierFlags.contains(.control) && flags.contains(.control)
        let optionWasPressed = !lastModifierFlags.contains(.option) && flags.contains(.option)

        // Toggle spelling when Ctrl is pressed
        if ctrlWasPressed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.viewModel.toggleSpelling()
                logDebug("⌃ Ctrl pressed → Toggle spelling: \(self.viewModel.isSpellingTempOff ? "OFF" : "ON")", source: self.logSource)
            }
        }

        // Toggle engine when Option is pressed
        if optionWasPressed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.viewModel.toggleEngine()
                logDebug("⌥ Option pressed → Toggle engine: \(self.viewModel.isEngineTempOff ? "OFF" : "ON")", source: self.logSource)
            }
        }

        // Update last state
        lastModifierFlags = flags
    }

    // MARK: - Positioning

    private let logSource = "TempOffToolbar"
    /// Only log positioning when explicitly showing (not during periodic updates)
    private var shouldLogPositioning = false

    private func positionNearCursor() {
        guard let panel = panel else { return }

        // Try to get cursor position from text field via Accessibility API
        if let cursorRect = getCursorRectFromAccessibility() {
            positionPanel(panel, relativeTo: cursorRect, isCursorRect: true)
        } else {
            // Fallback: position near mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            let mouseRect = NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 20)

            if shouldLogPositioning {
                logDebug("Fallback to mouse location: \(mouseLocation)", source: logSource)
            }

            positionPanel(panel, relativeTo: mouseRect, isCursorRect: false)
        }
    }

    private func positionPanel(_ panel: NSPanel, relativeTo targetRect: NSRect, isCursorRect: Bool) {
        let panelSize = panel.frame.size

        // Center horizontally on target cursor position
        var x = targetRect.origin.x - panelSize.width / 2 + targetRect.width / 2

        // Gap between toolbar and cursor (similar to macOS Fn popup)
        let gap: CGFloat = isCursorRect ? 4 : 8

        // Position ABOVE the target (like macOS Fn popup)
        // In Cocoa coords: higher Y = above
        var y = targetRect.origin.y + targetRect.height + gap

        // Find the screen that contains the target position
        let targetPoint = NSPoint(x: targetRect.midX, y: targetRect.midY)
        var containingScreen: NSScreen? = nil

        for screen in NSScreen.screens {
            if screen.frame.contains(targetPoint) {
                containingScreen = screen
                break
            }
        }

        // If no screen contains the point, find the nearest screen
        if containingScreen == nil {
            containingScreen = NSScreen.screens.min(by: { screen1, screen2 in
                let dist1 = distanceToScreen(point: targetPoint, screen: screen1)
                let dist2 = distanceToScreen(point: targetPoint, screen: screen2)
                return dist1 < dist2
            })
        }

        if shouldLogPositioning {
            logDebug("Target rect: \(targetRect)", source: logSource)
            logDebug("Target point: \(targetPoint)", source: logSource)
            logDebug("Containing screen: \(containingScreen?.frame ?? .zero)", source: logSource)
        }

        if let screen = containingScreen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Adjust horizontal position to stay within screen bounds
            x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - panelSize.width - 10))

            // If toolbar would go above screen top, position below target instead
            if y + panelSize.height > screenFrame.maxY {
                y = targetRect.origin.y - panelSize.height - gap
            }

            // Ensure not below screen bottom
            if y < screenFrame.minY {
                y = screenFrame.minY + 10
            }
        }

        if shouldLogPositioning {
            logDebug("Final panel position: (\(x), \(y))", source: logSource)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func distanceToScreen(point: NSPoint, screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        let clampedX = max(frame.minX, min(point.x, frame.maxX))
        let clampedY = max(frame.minY, min(point.y, frame.maxY))
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return sqrt(dx * dx + dy * dy)
    }

    /// Get cursor rectangle from focused text element via Accessibility API
    /// Returns coordinates in Cocoa screen space (origin at bottom-left)
    private func getCursorRectFromAccessibility() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            if shouldLogPositioning {
                logDebug("Cannot get focused element", source: logSource)
            }
            return nil
        }

        let axElement = focusedElement as! AXUIElement

        // Log element role for debugging
        if shouldLogPositioning {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                logDebug("Focused element role: \(role)", source: logSource)
            }
        }

        // Try Method 1: Get cursor position via AXBoundsForRange (works in most apps)
        if let cursorRect = getCursorBoundsViaRange(axElement) {
            return cursorRect
        }

        // Method 2: Try AXInsertionPointLineNumber combined with element bounds
        // This is useful for text editors that don't support AXBoundsForRange
        if let insertionRect = getInsertionPointBounds(axElement) {
            return insertionRect
        }

        // Fallback Method 3: Get the text field's position and size
        // Use just the top-left corner area for positioning
        if let fieldRect = getElementBounds(axElement) {
            if shouldLogPositioning {
                logDebug("Using element bounds fallback: \(fieldRect)", source: logSource)
            }
            // Return a small rect at the beginning of the field
            return NSRect(
                x: fieldRect.origin.x,
                y: fieldRect.origin.y + fieldRect.height - 20,  // Near top in Cocoa coords
                width: 2,
                height: 20
            )
        }

        return nil
    }

    /// Try to get insertion point bounds by combining line number with element bounds
    private func getInsertionPointBounds(_ element: AXUIElement) -> NSRect? {
        // Get visible character range to estimate line height
        var visibleRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &visibleRangeRef) == .success else {
            return nil
        }

        // Try to get bounds for visible range (gives us element content area)
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            visibleRangeRef!,
            &boundsRef
        ) == .success,
              let boundsValue = boundsRef else {
            return nil
        }

        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        if shouldLogPositioning {
            logDebug("Got visible range bounds (AX): \(axBounds)", source: logSource)
        }

        // Validate bounds - some apps return invalid bounds (width=0, height=0)
        if axBounds.width == 0 && axBounds.height == 0 {
            if shouldLogPositioning {
                logDebug("⚠️ Invalid visible range bounds (0x0), will fallback", source: logSource)
            }
            return nil
        }

        return convertAXToCocoaCoordinates(axBounds)
    }


    /// Get cursor bounds using AXBoundsForRangeParameterizedAttribute
    private func getCursorBoundsViaRange(_ element: AXUIElement) -> NSRect? {
        // Get selected text range (cursor position)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else {
            return nil
        }

        // Get bounds for the cursor position
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        ) == .success,
              let boundsValue = boundsRef else {
            return nil
        }

        // Extract CGRect from AXValue
        var axBounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axBounds) else {
            return nil
        }

        if shouldLogPositioning {
            logDebug("AX cursor bounds (raw): \(axBounds)", source: logSource)
        }

        // Validate bounds - some apps return invalid bounds (width=0, height=0)
        // or position at edge of screen (e.g., Y = screen height exactly)
        if axBounds.width == 0 && axBounds.height == 0 {
            if shouldLogPositioning {
                logDebug("⚠️ Invalid bounds (0x0), will fallback", source: logSource)
            }
            return nil
        }
        
        // If height is 0 but we have a valid X position, assume default line height
        if axBounds.height == 0 {
            axBounds.size.height = 18 // Default line height
        }

        let result = convertAXToCocoaCoordinates(axBounds)

        if shouldLogPositioning, let r = result {
            logDebug("Converted to Cocoa: \(r)", source: logSource)
        }

        return result
    }


    /// Get element bounds using AXPosition and AXSize attributes
    private func getElementBounds(_ element: AXUIElement) -> NSRect? {
        // Get position
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        // Get size
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        let axBounds = CGRect(origin: position, size: size)
        return convertAXToCocoaCoordinates(axBounds)
    }

    /// Convert AX coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
    /// Works correctly on multi-monitor setups
    private func convertAXToCocoaCoordinates(_ axRect: CGRect) -> NSRect? {
        // macOS coordinate systems:
        // - AX/CG/Quartz: Origin at TOP-LEFT of primary screen, Y increases DOWNWARD
        // - Cocoa/AppKit: Origin at BOTTOM-LEFT of primary screen, Y increases UPWARD
        //
        // For multi-monitor setups:
        // - Primary screen (NSScreen.screens[0]) always has frame.origin = (0, 0) in Cocoa
        // - Secondary screens below primary have NEGATIVE Y in Cocoa
        // - Secondary screens above primary have POSITIVE Y in Cocoa
        //
        // The key insight: We need to find the GLOBAL coordinate space that encompasses
        // all screens, then flip Y within that space.
        
        guard let primaryScreen = NSScreen.screens.first else {
            return nil
        }
        
        // Method: Use primary screen height as the pivot point for Y-axis flipping
        // This works because:
        // - AX Y=0 is at TOP of primary screen
        // - Cocoa Y=0 is at BOTTOM of primary screen
        // - Both share the same X coordinates
        // - Both extend into negative/positive Y for screens below/above primary
        //
        // Formula: cocoa_y = primaryHeight - ax_y - rect_height
        // This formula works for ALL screens because:
        // - For primary screen: ax_y is 0..primaryHeight, result is 0..primaryHeight ✓
        // - For screen below primary: ax_y > primaryHeight, result is negative Y ✓
        // - For screen above primary: ax_y < 0, result > primaryHeight ✓
        
        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - axRect.origin.y - axRect.height
        
        // X coordinate stays the same (both systems use same X axis)
        let cocoaX = axRect.origin.x

        if shouldLogPositioning {
            logDebug("=== Coordinate Conversion ===", source: logSource)
            logDebug("Input AX rect: \(axRect)", source: logSource)
            logDebug("Primary screen height: \(primaryHeight)", source: logSource)
            
            // Log all screens for debugging multi-monitor issues
            for (i, screen) in NSScreen.screens.enumerated() {
                let isPrimary = (i == 0 ? " (PRIMARY)" : "")
                logDebug("  Screen \(i)\(isPrimary): frame=\(screen.frame)", source: logSource)
            }
            
            logDebug("Calculated Cocoa position: (\(cocoaX), \(cocoaY))", source: logSource)
            
            // Validate: check if the result falls within any screen
            let resultPoint = NSPoint(x: cocoaX + axRect.width/2, y: cocoaY + axRect.height/2)
            var foundScreen: NSScreen? = nil
            for screen in NSScreen.screens {
                if screen.frame.contains(resultPoint) {
                    foundScreen = screen
                    break
                }
            }
            
            if let screen = foundScreen {
                logDebug("Result is on screen: \(screen.frame)", source: logSource)
            } else {
                // If result doesn't fall on any screen, log a warning
                logDebug("⚠️ Result point \(resultPoint) is NOT on any screen!", source: logSource)
                
                // Fallback: find nearest screen and clamp to it
                if let nearestScreen = NSScreen.screens.min(by: { screen1, screen2 in
                    let dist1 = distanceToScreen(point: resultPoint, screen: screen1)
                    let dist2 = distanceToScreen(point: resultPoint, screen: screen2)
                    return dist1 < dist2
                }) {
                    logDebug("Nearest screen: \(nearestScreen.frame)", source: logSource)
                }
            }
        }

        return NSRect(
            x: cocoaX,
            y: cocoaY,
            width: axRect.width,
            height: axRect.height
        )
    }

    // MARK: - Auto-hide

    private func setupAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard autoHideDelay > 0 else { return }

        hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    // MARK: - State Management

    /// Update temp off states from external source
    func updateStates(spellingTempOff: Bool, engineTempOff: Bool) {
        viewModel.updateStates(spellingTempOff: spellingTempOff, engineTempOff: engineTempOff)
    }

    /// Get current spelling temp off state
    var isSpellingTempOff: Bool {
        return viewModel.isSpellingTempOff
    }

    /// Get current engine temp off state
    var isEngineTempOff: Bool {
        return viewModel.isEngineTempOff
    }

    // MARK: - Resize

    private func resizePanelForContent() {
        guard let panel = panel,
              let hostingController = panel.contentViewController as? NSHostingController<TempOffToolbarView> else {
            return
        }

        // Update root view to trigger size recalculation
        hostingController.rootView = TempOffToolbarView(viewModel: viewModel)

        // Get fitting size
        let fittingSize = hostingController.view.fittingSize
        panel.setContentSize(fittingSize)
    }
}
