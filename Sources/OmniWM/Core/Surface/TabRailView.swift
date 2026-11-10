// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

final class TabRailView: NSView {
    private var tabs: [TabRailTabInfo] = []
    private let trackView: TabRailTrackView
    private let motionPolicy: MotionPolicy
    private let appInfoCache: AppInfoCache
    private var iconView: TabRailIconView?
    private var sidewaysView: TabRailSidewaysTabsView?
    private var pointerOverStrip = false
    private var pressTurnedIntoDrag = false
    private var isTravelling = false
    private var style: TabRailStyle = .compact
    private var railLayout = TabRailLayout.empty

    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            updateTrackView()
            if !isHovered {
                onHoverChange?(nil, nil)
            }
        }
    }

    private var hoveredVisualIndex: Int? {
        didSet {
            guard oldValue != hoveredVisualIndex else { return }
            updateTrackView()
        }
    }

    private var tracking: NSTrackingArea?
    private var accessibilityTabElements: [TabRailAccessibilityElement] = []
    private var suppressAccessibilityGeometryUpdates = false

    private var tabCount: Int {
        tabs.count
    }

    private var activeVisualIndex = 0

    var onSelect: ((Int) -> Void)?
    var onDrag: ((TabRailDragGesture.Event, CGPoint) -> Void)?
    var acceptsDrags: () -> Bool = { false }
    private var dragGesture = TabRailDragGesture()
    var onHoverChange: ((TabRailTabInfo?, CGRect?) -> Void)?

    init(frame frameRect: NSRect, motionPolicy: MotionPolicy, appInfoCache: AppInfoCache = AppInfoCache()) {
        self.motionPolicy = motionPolicy
        self.appInfoCache = appInfoCache
        trackView = TabRailTrackView(frame: .zero, motionPolicy: motionPolicy)
        super.init(frame: frameRect)
        addSubview(trackView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        tabs: [TabRailTabInfo],
        activeVisualIndex: Int,
        style: TabRailStyle = .compact,
        travellingTabTop: CGFloat? = nil
    ) {
        let styleChanged = self.style != style
        if styleChanged {
            invalidateHover()
            self.style = style
            configureStyle()
        }
        let metadataChanged = !Self.hasSameAccessibilityMetadata(self.tabs, tabs)
        let tabsChanged = self.tabs != tabs
        let activeChanged = self.activeVisualIndex != activeVisualIndex
        let countChanged = self.tabs.count != tabs.count
        self.tabs = tabs
        self.activeVisualIndex = activeVisualIndex
        if style == .appIcons {
            iconView?.update(tabs: tabs, activeVisualIndex: activeVisualIndex)
        }
        sidewaysView?.update(tabs: tabs, activeVisualIndex: activeVisualIndex, firstTabTop: travellingTabTop)
        if isTravelling != (travellingTabTop != nil) {
            isTravelling = travellingTabTop != nil
            applyTuck()
        }
        updateTrackView(rebuildLayout: countChanged || activeChanged || styleChanged)

        if metadataChanged || styleChanged {
            refreshAccessibilityElements()
        } else if activeChanged {
            refreshAccessibilityFrames()
            updateAccessibilitySelection(postNotification: true)
        }
        if tabsChanged || activeChanged {
            notifyHoverChange()
        }
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        guard sizeChanged else { return }
        iconView?.frame = bounds
        sidewaysView?.frame = bounds
        updateTrackView(rebuildLayout: true)
        if !suppressAccessibilityGeometryUpdates {
            refreshAccessibilityElements()
        }
    }

    func performWithoutAccessibilityGeometryUpdates(_ body: () -> Void) {
        suppressAccessibilityGeometryUpdates = true
        body()
        suppressAccessibilityGeometryUpdates = false
    }

    func refreshAppearance() {
        trackView.refreshAppearance()
        iconView?.refreshAppearance()
        sidewaysView?.refreshAppearance()
        updateTrackView()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateTrackView(rebuildLayout: true)
        refreshAccessibilityFrames()
    }

    func invalidateHover() {
        isHovered = false
        hoveredVisualIndex = nil
    }

    func refreshAccessibilityFrames() {
        let items = currentLayout().items
        guard items.count == accessibilityTabElements.count,
              zip(accessibilityTabElements, items).allSatisfy({ pair in
                  pair.0.visualIndex == pair.1.visualIndex
              })
        else {
            refreshAccessibilityElements()
            NSAccessibility.post(element: self, notification: .layoutChanged)
            return
        }
        for (element, item) in zip(accessibilityTabElements, items) {
            element.updateScreenFrame(screenFrame(for: item.hitRect))
        }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let nextTracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tracking = nextTracking
        addTrackingArea(nextTracking)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredVisualIndex(with: event)
        updateTuck(pointer: convert(event.locationInWindow, from: nil), buttonHeld: NSEvent.pressedMouseButtons != 0)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredVisualIndex(with: event)
        updateTuck(pointer: convert(event.locationInWindow, from: nil), buttonHeld: NSEvent.pressedMouseButtons != 0)
    }

    override func mouseExited(with _: NSEvent) {
        invalidateHover()
        updateTuck(pointer: nil)
    }

    private func updateTuck(pointer: CGPoint?, buttonHeld: Bool = false) {
        pointerOverStrip = !buttonHeld && pointer.map { point in
            point.x >= 0 && point.x < bounds.width - style.windowOverlap && point.y >= 0 && point.y <= bounds.height
        } ?? false
        applyTuck()
    }

    private func applyTuck() {
        sidewaysView?.showsTuck = !pointerOverStrip || pressTurnedIntoDrag || isTravelling
    }

    func tabTop(_ visualIndex: Int) -> CGFloat? {
        style == .sidewaysTabs ? sidewaysView?.tabTop(visualIndex) : nil
    }

    override func shouldDelayWindowOrdering(for _: NSEvent) -> Bool {
        style == .sidewaysTabs
    }

    override func mouseDown(with event: NSEvent) {
        if style == .sidewaysTabs { NSApp.preventWindowOrdering() }
        let point = convert(event.locationInWindow, from: nil)
        pressTurnedIntoDrag = false
        updateTuck(pointer: point)
        guard let item = item(at: point) else { return }
        dragGesture.press(visualIndex: item.visualIndex, at: NSEvent.mouseLocation)
        onSelect?(item.visualIndex)
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsDrags() else { return super.mouseDragged(with: event) }
        let location = NSEvent.mouseLocation
        guard let gestureEvent = dragGesture.drag(to: location) else { return }
        if !pressTurnedIntoDrag {
            pressTurnedIntoDrag = true
            updateTuck(pointer: convert(event.locationInWindow, from: nil))
        }
        onDrag?(gestureEvent, location)
    }

    override func mouseUp(with event: NSEvent) {
        dragGesture.release()
        pressTurnedIntoDrag = false
        updateTuck(pointer: convert(event.locationInWindow, from: nil))
        guard acceptsDrags() else { return super.mouseUp(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        if style == .appIcons {
            iconView?.scrollWheel(with: event)
        } else if style == .sidewaysTabs {
            sidewaysView?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    func item(at point: CGPoint) -> TabRailLayout.Item? {
        if style != .compact {
            return currentLayout().items.first { !$0.hitRect.isEmpty && $0.hitRect.contains(point) }
        }
        guard railLayout.railRect.contains(point) else { return nil }
        let markerRects = trackView.presentedMarkerRects()
        let hitRects = TabRailSegmentGeometry.hitRects(markerRects: markerRects, railRect: railLayout.railRect)
        guard let item = railLayout.items.first(where: { hitRects[$0.visualIndex]?.contains(point) == true }),
              let hitRect = hitRects[item.visualIndex],
              let markerRect = markerRects[item.visualIndex] else { return nil }
        return .init(visualIndex: item.visualIndex, hitRect: hitRect, pillRect: markerRect)
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityChildren() -> [Any]? {
        accessibilityTabElements
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        accessibilityTabElements.filter(\.isSelected)
    }

    override func accessibilityLabel() -> String? {
        String(localized: "Window tabs")
    }

    override func accessibilityValue() -> Any? {
        guard tabCount > 0 else { return String(localized: "No tabs") }
        let clampedActiveVisualIndex = min(max(0, activeVisualIndex), tabCount - 1)
        return String(localized: "Tab \(clampedActiveVisualIndex + 1) of \(tabCount) selected")
    }

    override func accessibilityHelp() -> String? {
        switch style {
        case .compact: String(localized: "Click a segment to select that tab.")
        case .appIcons: String(localized: "Click an app icon to select its window. Scroll to see more tabs.")
        case .sidewaysTabs: String(localized: "Click a tab to select its window. Scroll to see more tabs.")
        }
    }

    private func updateHoveredVisualIndex(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let item = item(at: point)
        let changed = !isHovered || hoveredVisualIndex != item?.visualIndex
        isHovered = item != nil
        hoveredVisualIndex = item?.visualIndex
        guard changed else { return }
        let tab = tabs.first { $0.visualIndex == item?.visualIndex }
        onHoverChange?(tab, item?.pillRect)
    }

    private func updateTrackView(rebuildLayout: Bool = false) {
        guard style == .compact else {
            iconView?.updateHover(hoveredVisualIndex)
            sidewaysView?.updateHover(hoveredVisualIndex)
            return
        }
        if rebuildLayout {
            railLayout = TabRailLayout(
                tabCount: tabCount,
                bounds: bounds,
                activeVisualIndex: activeVisualIndex,
                scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            )
            trackView.frame = railLayout.barRect
        }
        trackView.update(
            layout: railLayout,
            activeVisualIndex: activeVisualIndex,
            hoveredVisualIndex: hoveredVisualIndex,
            railHovered: isHovered
        )
    }

    private func notifyHoverChange() {
        guard isHovered,
              let hoveredVisualIndex,
              let tab = tabs.first(where: { $0.visualIndex == hoveredVisualIndex }),
              let item = currentLayout().items.first(where: { $0.visualIndex == hoveredVisualIndex })
        else {
            onHoverChange?(nil, nil)
            return
        }
        onHoverChange?(tab, item.pillRect)
    }

    private func currentLayout() -> TabRailLayout {
        switch style {
        case .compact: railLayout
        case .appIcons: iconView?.railLayout(in: self) ?? .empty
        case .sidewaysTabs: sidewaysView?.railLayout(in: self) ?? .empty
        }
    }

    private func configureStyle() {
        trackView.isHidden = style != .compact
        if style == .appIcons {
            let icons = TabRailIconView(motionPolicy: motionPolicy, appInfoCache: appInfoCache)
            icons.frame = bounds
            icons.onWillScroll = { [weak self] in self?.invalidateHover() }
            icons.onDidScroll = { [weak self] in
                guard let self, !suppressAccessibilityGeometryUpdates else { return }
                refreshAccessibilityFrames()
            }
            iconView = icons
            addSubview(icons)
        } else {
            iconView?.removeFromSuperview()
            iconView = nil
        }
        if style == .sidewaysTabs {
            let strip = TabRailSidewaysTabsView(appInfoCache: appInfoCache)
            strip.frame = bounds
            strip.onWillScroll = { [weak self] in self?.invalidateHover() }
            strip.onDidScroll = { [weak self] in
                guard let self, !suppressAccessibilityGeometryUpdates else { return }
                refreshAccessibilityFrames()
            }
            sidewaysView = strip
            addSubview(strip)
        } else {
            sidewaysView?.removeFromSuperview()
            sidewaysView = nil
        }
    }
}

extension TabRailView {
    private func refreshAccessibilityElements() {
        let layout = currentLayout()
        let tabsByVisualIndex = Dictionary(tabs.map { ($0.visualIndex, $0) }, uniquingKeysWith: { first, _ in first })
        let existingElements = Dictionary(
            accessibilityTabElements.map { ($0.visualIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        accessibilityTabElements = layout.items.compactMap { item in
            guard let tab = tabsByVisualIndex[item.visualIndex] else {
                return nil
            }
            let screenFrame = screenFrame(for: item.hitRect)
            if let element = existingElements[item.visualIndex] {
                element.update(tab: tab, screenFrame: screenFrame)
                return element
            }
            let element = TabRailAccessibilityElement(
                parent: self,
                tab: tab,
                screenFrame: screenFrame,
                pressAction: { [weak self] visualIndex in
                    _ = self?.performAccessibilitySelection(visualIndex)
                },
                revealAction: { [weak self] visualIndex in
                    self?.iconView?.reveal(visualIndex)
                    self?.sidewaysView?.reveal(visualIndex)
                }
            )
            return element
        }
        updateAccessibilitySelection(postNotification: false)
    }

    private func updateAccessibilitySelection(postNotification: Bool) {
        for element in accessibilityTabElements {
            element.updateSelected(element.visualIndex == activeVisualIndex, postNotification: postNotification)
        }
    }

    private func performAccessibilitySelection(_ visualIndex: Int) -> Bool {
        guard tabs.contains(where: { $0.visualIndex == visualIndex }) else { return false }
        iconView?.reveal(visualIndex)
        sidewaysView?.reveal(visualIndex)
        onSelect?(visualIndex)
        return true
    }

    private func screenFrame(for rect: CGRect) -> CGRect {
        guard let window, !rect.isEmpty else { return .zero }
        let windowRect = convert(rect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private static func hasSameAccessibilityMetadata(
        _ lhs: [TabRailTabInfo],
        _ rhs: [TabRailTabInfo]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.visualIndex == right.visualIndex,
                  left.windowId == right.windowId,
                  left.appName == right.appName,
                  left.title == right.title
            else {
                return false
            }
        }
        return true
    }
}
