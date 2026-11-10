// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import QuartzCore

@MainActor
final class SidewaysTabLayers {
    let shape = CAShapeLayer()
    let content = CALayer()
    private var contentKey: SidewaysTabContent.Key?

    private static let animatedKeys = [
        "path", "fillColor", "strokeColor", "lineWidth", "shadowPath", "shadowOpacity", "shadowRadius",
        "shadowOffset", "shadowColor", "position", "bounds", "frame", "zPosition", "contents", "contentsScale",
        "hidden", "anchorPoint", "onOrderIn", "onOrderOut", "sublayers"
    ]

    init() {
        let noActions = Dictionary(uniqueKeysWithValues: Self.animatedKeys.map { ($0, NSNull() as any CAAction) })
        shape.actions = noActions
        content.actions = noActions
        shape.shadowColor = CGColor(gray: 0, alpha: 1)
        shape.lineWidth = 1
        shape.strokeColor = nil
        content.contentsGravity = .resize
    }

    func applyShape(
        path: CGPath,
        fill: CGColor,
        outline: CGColor?,
        shadow: (opacity: CGFloat, blur: CGFloat),
        shadowDown: CGFloat,
        order: CGFloat
    ) {
        let metrics = TabRailRenderMetricsRecorder.shared
        if shape.path != path {
            shape.path = path
            shape.shadowPath = path
            metrics.noteShapeUpdate()
        }
        if shape.fillColor != fill {
            shape.fillColor = fill
            metrics.noteFillUpdate()
        }
        if shape.strokeColor != outline { shape.strokeColor = outline }
        let opacity = Float(shadow.opacity)
        if shape.shadowOpacity != opacity { shape.shadowOpacity = opacity }
        let radius = shadow.blur / 2
        if shape.shadowRadius != radius { shape.shadowRadius = radius }
        let offset = CGSize(width: 0, height: shadowDown)
        if shape.shadowOffset != offset { shape.shadowOffset = offset }
        if shape.zPosition != order {
            shape.zPosition = order
            metrics.noteOrderUpdate()
        }
    }

    func applyContent(
        key: SidewaysTabContent.Key,
        icon: NSImage?,
        labelColor: NSColor,
        frame: CGRect,
        scale: CGFloat,
        order: CGFloat
    ) {
        if contentKey != key {
            content.contents = SidewaysTabContent.image(for: key, icon: icon, labelColor: labelColor)
            contentKey = key
        }
        if content.frame != frame { content.frame = frame }
        if content.contentsScale != scale { content.contentsScale = scale }
        if content.zPosition != order { content.zPosition = order }
    }

    func removeFromSuperlayer() {
        shape.removeFromSuperlayer()
        content.removeFromSuperlayer()
    }
}

@MainActor
enum SidewaysTabContent {
    struct Key: Hashable {
        let label: String?
        let icon: ObjectIdentifier?
        let active: Bool
        let labelColor: [Int]
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat

        init(label: String?, icon: NSImage?, size: CGSize, active: Bool, labelColor: NSColor, scale: CGFloat) {
            self.label = label
            self.icon = icon.map(ObjectIdentifier.init)
            self.active = active
            let rgb = labelColor.usingColorSpace(.sRGB)
            self.labelColor = [
                rgb?.redComponent, rgb?.greenComponent, rgb?.blueComponent, rgb?.alphaComponent
            ].map { Int((($0 ?? 0) * 255).rounded()) }
            width = size.width
            height = size.height
            self.scale = scale
        }
    }

    private static var images: [Key: CGImage] = [:]
    private static let imageCacheLimit = 128
    private static let activeFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private static let inactiveFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static let fallbackIcon = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
    private static let truncatingParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }()

    static func font(active: Bool) -> NSFont {
        active ? activeFont : inactiveFont
    }

    static func image(for key: Key, icon: NSImage?, labelColor: NSColor) -> CGImage? {
        let metrics = TabRailRenderMetricsRecorder.shared
        if let image = images[key] {
            metrics.noteContentReuse()
            return image
        }
        let size = CGSize(width: key.width, height: key.height)
        guard let image = render(
            label: key.label, icon: icon, size: size, active: key.active, labelColor: labelColor, scale: key.scale
        ) else { return nil }
        metrics.noteContentRender(area: size.width * size.height)
        if images.count >= imageCacheLimit { images.removeAll(keepingCapacity: true) }
        images[key] = image
        return image
    }

    static func render(
        label: String?, icon: NSImage?, size: CGSize, active: Bool, labelColor: NSColor, scale: CGFloat
    ) -> CGImage? {
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(label: label, icon: icon, in: CGRect(origin: .zero, size: size), active: active, labelColor: labelColor)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    static func draw(label: String?, icon: NSImage?, in rect: CGRect, active: Bool, labelColor: NSColor) {
        let length = rect.height
        let width = rect.width
        let iconSize = SidewaysTabMetrics.iconSize
        let iconX = label == nil ? (length - iconSize) / 2 : SidewaysTabMetrics.contentEndInset
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.rotate(byRadians: -.pi / 2)
        transform.concat()
        if let icon = icon ?? fallbackIcon {
            let iconRect = CGRect(x: iconX, y: (width - iconSize) / 2, width: iconSize, height: iconSize)
            draw(icon, in: iconRect, tint: icon.isTemplate ? labelColor : nil)
        }
        guard let label else { return }
        let font = font(active: active)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor,
            .paragraphStyle: truncatingParagraph
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
}
