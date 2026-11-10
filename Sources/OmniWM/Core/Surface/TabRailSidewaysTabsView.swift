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
            document.needsDisplay = true
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
        let membershipChanged = self.tabs.map(\.token) != tabs.map(\.token)
            || self.tabs.map(TabRailSidewaysTabsDocumentView.label(for:))
            != tabs.map(TabRailSidewaysTabsDocumentView.label(for:))
        let activeChanged = self.activeVisualIndex != activeVisualIndex
        let topChanged = self.firstTabTop != firstTabTop
        self.firstTabTop = firstTabTop
        guard membershipChanged || activeChanged || topChanged || self.tabs != tabs else { return }
        self.tabs = tabs
        self.activeVisualIndex = activeVisualIndex
        document.tabs = tabs
        document.activeVisualIndex = activeVisualIndex
        if membershipChanged || activeChanged || topChanged {
            layoutDocument()
            reveal(activeVisualIndex)
        }
        document.needsDisplay = true
    }

    func updateHover(_ visualIndex: Int?) {
        guard document.hoveredVisualIndex != visualIndex else { return }
        document.hoveredVisualIndex = visualIndex
        document.needsDisplay = true
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
        document.needsDisplay = true
    }

    private func layoutDocument() {
        let lengths = tabs.map { tab in
            SidewaysTabMetrics.labelledLength(
                labelWidth: Self.labelWidth(TabRailSidewaysTabsDocumentView.label(for: tab))
            )
        }
        let layout = SidewaysTabLayout(
            labelledLengths: lengths, viewportLength: bounds.height,
            width: min(bounds.width, SidewaysTabMetrics.stripWidth),
            activeVisualIndex: activeVisualIndex,
            firstTabTop: firstTabTop
        )
        let size = CGSize(width: bounds.width, height: layout.documentLength)
        guard layout != document.layout || size != document.frame.size else { return }
        document.layout = layout
        document.setFrameSize(size)
        scroll(to: scrollView.contentView.bounds.origin)
        document.needsDisplay = true
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

    override var isFlipped: Bool {
        true
    }

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let active = layout.tabRects.indices.contains(activeVisualIndex) ? activeVisualIndex : nil
        for index in layout.tabRects.indices.reversed() where index != active {
            let colors = colors(at: index, active: false, dark: dark)
            let shape = Self.tabPath(in: layout.tabRects[index])
            drawShape(shape, fill: colors.fill, shadowAlpha: 0.3, blur: 4, highContrast: highContrast, in: context)
            drawContent(at: index, active: false, label: colors.label)
        }
        guard let active else { return }
        let colors = colors(at: active, active: true, dark: dark)
        let shape = CGMutablePath()
        shape.addPath(Self.tabPath(in: layout.tabRects[active]))
        let bandRadius = SidewaysTabMetrics.bandWidth / 2
        shape.addRoundedRect(
            in: layout.bandRect(reaching: showsTuck ? bounds.maxX : min(bounds.maxX, SidewaysTabMetrics.stripWidth)),
            cornerWidth: bandRadius,
            cornerHeight: bandRadius
        )
        drawShape(shape, fill: colors.fill, shadowAlpha: 0.4, blur: 6, highContrast: highContrast, in: context)
        drawContent(at: active, active: true, label: colors.label)
    }

    private func colors(at index: Int, active: Bool, dark: Bool) -> TabRailTabColor.Shades {
        TabRailTabColor.shades(
            base: tabs.indices.contains(index)
                ? TabRailTabColor.baseColor(for: tabs[index].icon, app: tabs[index].token?.pid) : nil,
            hovered: !active && index == hoveredVisualIndex,
            dark: dark
        )
    }

    private func drawShape(
        _ shape: CGPath, fill: NSColor, shadowAlpha: CGFloat, blur: CGFloat, highContrast: Bool,
        in context: CGContext
    ) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2), blur: blur,
            color: NSColor.black.withAlphaComponent(shadowAlpha).cgColor
        )
        context.addPath(shape)
        context.setFillColor(fill.cgColor)
        context.fillPath()
        context.restoreGState()
        guard highContrast else { return }
        context.addPath(shape)
        context.setStrokeColor(NSColor.labelColor.cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }

    private func drawContent(at index: Int, active: Bool, label: NSColor) {
        guard tabs.indices.contains(index), layout.hitRects.indices.contains(index) else { return }
        drawContent(of: tabs[index], in: layout.hitRects[index], active: active, labelColor: label)
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

    private static let activeFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private static let inactiveFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let fallbackIcon = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
    private static let truncatingParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }()

    static func font(active: Bool) -> NSFont {
        active ? activeFont : inactiveFont
    }

    private func drawContent(of tab: TabRailTabInfo, in rect: CGRect, active: Bool, labelColor: NSColor) {
        let length = rect.height
        let width = rect.width
        let iconSize = SidewaysTabMetrics.iconSize
        let label = layout.showsLabels ? Self.label(for: tab) : nil
        let iconX = label == nil ? (length - iconSize) / 2 : SidewaysTabMetrics.contentEndInset
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.rotate(byRadians: -.pi / 2)
        transform.concat()
        if let icon = tab.icon ?? Self.fallbackIcon {
            let iconRect = CGRect(x: iconX, y: (width - iconSize) / 2, width: iconSize, height: iconSize)
            Self.draw(icon, in: iconRect, tint: icon.isTemplate ? labelColor : nil)
        }
        guard let label else { return }
        let font = Self.font(active: active)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor,
            .paragraphStyle: Self.truncatingParagraph
        ]
        let labelX = iconX + iconSize + SidewaysTabMetrics.iconLabelGap
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let labelRect = CGRect(
            x: labelX, y: (width - lineHeight) / 2,
            width: max(0, length - labelX - SidewaysTabMetrics.contentEndInset), height: lineHeight
        )
        NSAttributedString(string: label, attributes: attributes)
            .draw(with: labelRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private static func draw(_ icon: NSImage, in rect: CGRect, tint: NSColor?) {
        guard let tint else {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        tint.setFill()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
    }

    static func label(for tab: TabRailTabInfo) -> String {
        tab.appName?.nilIfEmpty ?? tab.title?.nilIfEmpty ?? String(localized: "Window \(tab.visualIndex + 1)")
    }
}
