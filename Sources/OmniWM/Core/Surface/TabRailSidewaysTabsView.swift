// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

final class TabRailSidewaysTabsView: NSView {
    let scrollView = NSScrollView()
    let document = TabRailSidewaysTabsDocumentView()
    private let appInfoCache: AppInfoCache
    private(set) var tabs: [TabRailTabInfo] = []
    private(set) var activeVisualIndex = 0
    private(set) var firstTabTop: CGFloat?
    var showsTuck = true {
        didSet {
            guard showsTuck != oldValue else { return }
            document.showsTuck = showsTuck
            document.invalidate(.tuck)
        }
    }

    var onWillScroll: (() -> Void)?
    var onDidScroll: (() -> Void)?

    init(appInfoCache: AppInfoCache) {
        self.appInfoCache = appInfoCache
        super.init(frame: .zero)
        wantsLayer = true
        let clip = scrollView.contentView
        clip.drawsBackground = false
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsChanged), name: NSView.boundsDidChangeNotification, object: clip
        )
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = document
        addSubview(scrollView)
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func scrollWheel(with event: NSEvent) {
        onWillScroll?()
        scrollView.scrollWheel(with: event)
    }

    @objc private func clipBoundsChanged() {
        onWillScroll?()
        onDidScroll?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let wasEmpty = bounds.height == 0
        super.setFrameSize(newSize)
        scrollView.frame = bounds
        layoutDocument()
        if wasEmpty, newSize.height > 0 { reveal(activeVisualIndex) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func update(tabs: [TabRailTabInfo], activeVisualIndex: Int, firstTabTop: CGFloat? = nil) {
        let tabs = tabs.map { tab in
            var tab = tab
            if tab.icon == nil { tab.icon = tab.token.flatMap { appInfoCache.info(for: $0.pid)?.icon } }
            return tab
        }
        let drawnChanged = Self.drawn(self.tabs) != Self.drawn(tabs)
        let activeChanged = self.activeVisualIndex != activeVisualIndex
        let topChanged = self.firstTabTop != firstTabTop
        self.tabs = tabs
        self.firstTabTop = firstTabTop
        self.activeVisualIndex = activeVisualIndex
        guard drawnChanged || activeChanged || topChanged else {
            TabRailRenderMetricsRecorder.shared.noteSkippedUpdate()
            return
        }
        document.tabs = tabs
        document.activeVisualIndex = activeVisualIndex
        layoutDocument()
        reveal(activeVisualIndex)
        document.invalidate(.tabs)
    }

    private struct DrawnTab: Equatable {
        let token: WindowToken?
        let label: String
        let icon: ObjectIdentifier?
    }

    private static func drawn(_ tabs: [TabRailTabInfo]) -> [DrawnTab] {
        tabs.map { tab in
            DrawnTab(
                token: tab.token,
                label: TabRailSidewaysTabsDocumentView.label(for: tab),
                icon: tab.icon.map(ObjectIdentifier.init)
            )
        }
    }

    func updateHover(_ visualIndex: Int?) {
        guard document.hoveredVisualIndex != visualIndex else { return }
        document.hoveredVisualIndex = visualIndex
        document.invalidate(.hover)
    }

    func reveal(_ visualIndex: Int) {
        guard document.layout.hitRects.indices.contains(visualIndex) else { return }
        let rect = document.layout.hitRects[visualIndex]
            .insetBy(dx: 0, dy: -SidewaysTabMetrics.stripEndPadding)
        let visible = scrollView.contentView.bounds
        var origin = visible.origin
        if rect.height > visible.height {
            origin.y = rect.midY - visible.height / 2
        } else if rect.minY < visible.minY {
            origin.y = rect.minY
        } else if rect.maxY > visible.maxY {
            origin.y = rect.maxY - visible.height
        }
        scroll(to: origin)
    }

    func tabTop(_ visualIndex: Int) -> CGFloat? {
        guard document.layout.tabRects.indices.contains(visualIndex) else { return nil }
        return document.layout.tabRects[visualIndex].minY - scrollView.contentView.bounds.minY
    }

    func railLayout(in view: NSView) -> TabRailLayout {
        let viewport = convert(bounds, to: view)
        let items = document.layout.hitRects.enumerated().map { index, rect in
            let hit = document.convert(rect, to: view).intersection(viewport)
            let visible = hit.isNull ? CGRect.zero : hit
            return TabRailLayout.Item(visualIndex: index, hitRect: visible, pillRect: visible)
        }
        return TabRailLayout(railRect: viewport, barRect: viewport, items: items)
    }

    func refreshAppearance() {
        document.invalidate(.appearance)
    }

    private func layoutDocument() {
        let lengths = tabs.map { tab in
            SidewaysTabMetrics.contentLength(
                labelWidth: Self.labelWidth(TabRailSidewaysTabsDocumentView.label(for: tab))
            )
        }
        let layout = SidewaysTabLayout(
            contentLengths: lengths, viewportLength: bounds.height,
            width: min(bounds.width, SidewaysTabMetrics.stripWidth),
            activeVisualIndex: activeVisualIndex,
            firstTabTop: firstTabTop
        )
        let size = CGSize(width: bounds.width, height: layout.documentLength)
        guard layout != document.layout || size != document.frame.size else { return }
        document.layout = layout
        document.setFrameSize(size)
        scroll(to: scrollView.contentView.bounds.origin)
        document.invalidate(.layout)
    }

    private static var labelWidths: [String: CGFloat] = [:]
    private static let labelWidthCacheLimit = 256

    static func labelWidth(_ label: String) -> CGFloat {
        if let width = labelWidths[label] { return width }
        if labelWidths.count >= labelWidthCacheLimit { labelWidths.removeAll(keepingCapacity: true) }
        let width = ceil(NSAttributedString(
            string: label, attributes: [.font: TabRailSidewaysTabsDocumentView.font(active: true)]
        ).size().width)
        labelWidths[label] = width
        return width
    }

    private func scroll(to origin: CGPoint) {
        let clip = scrollView.contentView
        let maxOffset = max(0, document.bounds.height - clip.bounds.height)
        let target = CGPoint(x: 0, y: min(max(0, origin.y), maxOffset))
        guard clip.bounds.origin != target else { return }
        onWillScroll?()
        clip.scroll(to: target)
        scrollView.reflectScrolledClipView(clip)
    }
}

final class TabRailSidewaysTabsDocumentView: NSView {
    var tabs: [TabRailTabInfo] = []
    var activeVisualIndex = 0
    var hoveredVisualIndex: Int?
    var showsTuck = true
    var layout = SidewaysTabLayout.empty
    private var pendingCause: TabRailRenderMetricsRecorder.UpdateCause?
    private var groups: [SidewaysTabLayers] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    func tabLayers(at index: Int) -> SidewaysTabLayers? {
        groups.indices.contains(index) ? groups[index] : nil
    }

    var hasPendingLayerUpdate: Bool {
        pendingCause != nil
    }

    func invalidate(_ cause: TabRailRenderMetricsRecorder.UpdateCause) {
        if pendingCause == nil { pendingCause = cause }
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        invalidate(.appearance)
    }

    override func updateLayer() {
        TabRailRenderMetricsRecorder.shared.notePass(pendingCause ?? .layout)
        pendingCause = nil
        applyLayers()
    }

    func applyLayers() {
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outline = highContrast ? Self.resolvedLabelColor(in: effectiveAppearance) : nil
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let down: CGFloat = root.contentsAreFlipped() ? 2 : -2
        let count = layout.tabRects.count
        while groups.count < count {
            let group = SidewaysTabLayers()
            root.addSublayer(group.shape)
            root.addSublayer(group.content)
            groups.append(group)
        }
        while groups.count > count {
            groups.removeLast().removeFromSuperlayer()
        }
        let active = layout.tabRects.indices.contains(activeVisualIndex) ? activeVisualIndex : nil
        for index in 0 ..< count {
            let isActive = index == active
            let shades = colors(at: index, active: isActive, dark: dark)
            let shape = CGMutablePath()
            shape.addPath(Self.tabPath(in: layout.tabRects[index]))
            if isActive {
                let bandRadius = SidewaysTabMetrics.bandWidth / 2
                shape.addRoundedRect(
                    in: layout.bandRect(
                        reaching: showsTuck ? bounds.maxX : min(bounds.maxX, SidewaysTabMetrics.stripWidth)
                    ),
                    cornerWidth: bandRadius, cornerHeight: bandRadius
                )
            }
            let order = isActive ? CGFloat(2 * count) : CGFloat(2 * (count - 1 - index))
            groups[index].applyShape(
                path: shape, fill: shades.fill.cgColor, outline: outline,
                shadow: isActive ? (opacity: 0.4, blur: 6) : (opacity: 0.3, blur: 4),
                shadowDown: down, order: order
            )
            guard tabs.indices.contains(index), layout.contentRects.indices.contains(index) else { continue }
            let rect = layout.contentRects[index]
            let label = layout.showsLabels ? Self.label(for: tabs[index]) : nil
            let icon = tabs[index].icon
            groups[index].applyContent(
                key: SidewaysTabContent.Key(
                    label: label, icon: icon, size: rect.size, active: isActive, labelColor: shades.label,
                    scale: scale
                ),
                icon: icon, labelColor: shades.label, frame: rect, scale: scale, order: order + 1
            )
        }
    }

    private static func resolvedLabelColor(in appearance: NSAppearance) -> CGColor {
        var color = NSColor.labelColor.cgColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.cgColor }
        return color
    }

    private func colors(at index: Int, active: Bool, dark: Bool) -> TabRailTabColor.Shades {
        TabRailTabColor.shades(
            base: tabs.indices.contains(index)
                ? TabRailTabColor.baseColor(for: tabs[index].icon, app: tabs[index].token?.pid) : nil,
            hovered: !active && index == hoveredVisualIndex,
            dark: dark
        )
    }

    static func tabPath(in rect: CGRect) -> CGPath {
        let radius = min(SidewaysTabMetrics.tabCornerRadius, rect.height / 2)
        let join = SidewaysTabMetrics.joinSize
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY - join))
        path.addArc(
            center: CGPoint(x: rect.maxX - join, y: rect.minY - join),
            radius: join, startAngle: 0, endAngle: .pi / 2, clockwise: false
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - join, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - join, y: rect.maxY + join),
            radius: join, startAngle: -.pi / 2, endAngle: 0, clockwise: false
        )
        path.closeSubpath()
        return path
    }

    static func font(active: Bool) -> NSFont {
        SidewaysTabContent.font(active: active)
    }

    static func label(for tab: TabRailTabInfo) -> String {
        tab.appName?.nilIfEmpty ?? tab.title?.nilIfEmpty ?? String(localized: "Window \(tab.visualIndex + 1)")
    }
}
