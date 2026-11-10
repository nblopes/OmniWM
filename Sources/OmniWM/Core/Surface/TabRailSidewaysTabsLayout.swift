// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

enum SidewaysTabMetrics {
    static let stripWidth: CGFloat = 40
    static let maximumTabLength: CGFloat = 190
    static let overlap: CGFloat = 12
    static let stripEndPadding: CGFloat = 10
    static let windowCornerAllowance: CGFloat = 26
    static let leadingInset: CGFloat = 4
    static let bandWidth: CGFloat = 4
    static let tuckUnderWindow: CGFloat = 10
    static let joinSize: CGFloat = 10
    static let tabCornerRadius: CGFloat = 10
    static let iconSize: CGFloat = 20
    static let contentEndInset: CGFloat = 14
    static let iconLabelGap: CGFloat = 10
    static let iconOnlyLength: CGFloat = 2 * contentEndInset + iconSize

    static func labelledLength(labelWidth: CGFloat) -> CGFloat {
        min(maximumTabLength, iconOnlyLength + iconLabelGap + max(0, labelWidth) + overlap)
    }
}

struct SidewaysTabLayout: Equatable {
    let showsLabels: Bool
    let documentLength: CGFloat
    let tabRects: [CGRect]
    let hitRects: [CGRect]

    static let empty = SidewaysTabLayout(labelledLengths: [], viewportLength: 0, width: 0)

    init(
        labelledLengths: [CGFloat],
        viewportLength: CGFloat,
        width: CGFloat,
        activeVisualIndex: Int? = nil,
        firstTabTop: CGFloat? = nil
    ) {
        let padding = SidewaysTabMetrics.stripEndPadding
        guard !labelledLengths.isEmpty,
              width > SidewaysTabMetrics.leadingInset + SidewaysTabMetrics.bandWidth
        else {
            showsLabels = false
            documentLength = max(0, viewportLength)
            tabRects = []
            hitRects = []
            return
        }
        let labelled = Self.stack(contentLengths: labelledLengths)
        let fitsLabels = Self.extent(of: labelled) + 2 * padding <= viewportLength
        let visibleLengths = fitsLabels
            ? labelledLengths.map { min(SidewaysTabMetrics.maximumTabLength, $0) }
            : Array(repeating: SidewaysTabMetrics.iconOnlyLength, count: labelledLengths.count)
        let stacked = fitsLabels ? labelled : Self.stack(contentLengths: visibleLengths)
        showsLabels = fitsLabels
        let extent = Self.extent(of: stacked)
        let shift = firstTabTop.map { min(max(0, $0 - padding), max(0, viewportLength - 2 * padding - extent)) } ?? 0
        documentLength = max(viewportLength, extent + 2 * padding + shift)
        let x = SidewaysTabMetrics.leadingInset
        let tabWidth = width - x - SidewaysTabMetrics.bandWidth
        let rects = stacked.map { CGRect(x: x, y: padding + shift + $0.start, width: tabWidth, height: $0.length) }
        tabRects = rects
        var hits = zip(rects, visibleLengths).map { rect, visible in
            CGRect(x: rect.minX, y: rect.maxY - visible, width: rect.width, height: visible)
        }
        if let active = activeVisualIndex, rects.indices.contains(active) {
            hits[active] = rects[active]
            if active > 0 {
                let above = hits[active - 1]
                hits[active - 1] = CGRect(
                    x: above.minX, y: above.minY, width: above.width,
                    height: max(0, rects[active].minY - above.minY)
                )
            }
        }
        hitRects = hits
    }

    func bandRect(reaching maxX: CGFloat) -> CGRect {
        guard let first = tabRects.first, maxX > first.maxX else { return .zero }
        return CGRect(x: first.maxX, y: 0, width: maxX - first.maxX, height: documentLength)
    }

    private static func stack(contentLengths: [CGFloat]) -> [(start: CGFloat, length: CGFloat)] {
        var result: [(start: CGFloat, length: CGFloat)] = []
        var visibleStart: CGFloat = 0
        for (index, content) in contentLengths.enumerated() {
            let visible = min(SidewaysTabMetrics.maximumTabLength, content)
            let hidden = index == 0 ? 0 : SidewaysTabMetrics.overlap
            result.append((start: visibleStart - hidden, length: visible + hidden))
            visibleStart += visible
        }
        return result
    }

    private static func extent(of stack: [(start: CGFloat, length: CGFloat)]) -> CGFloat {
        stack.last.map { $0.start + $0.length } ?? 0
    }

    static func fittedHeight(tabCount: Int, availableHeight: CGFloat) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let usable = availableHeight - 2 * SidewaysTabMetrics.windowCornerAllowance
        guard usable >= SidewaysTabMetrics.iconOnlyLength + 2 * SidewaysTabMetrics.stripEndPadding else { return 0 }
        return usable
    }
}
