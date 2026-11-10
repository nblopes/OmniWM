// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

enum SidewaysTabMetrics {
    static let stripWidth: CGFloat = 40
    static let maximumTabLength: CGFloat = 190
    static let maximumContentLength: CGFloat = maximumTabLength - overlap
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

    static func contentLength(labelWidth: CGFloat) -> CGFloat {
        min(maximumContentLength, iconOnlyLength + iconLabelGap + max(0, labelWidth))
    }
}

struct SidewaysTabLayout: Equatable {
    let showsLabels: Bool
    let documentLength: CGFloat
    let tabRects: [CGRect]
    let hitRects: [CGRect]
    let contentRects: [CGRect]

    static let empty = SidewaysTabLayout(contentLengths: [], viewportLength: 0, width: 0)

    init(
        contentLengths: [CGFloat],
        viewportLength: CGFloat,
        width: CGFloat,
        activeVisualIndex: Int? = nil,
        firstTabTop: CGFloat? = nil
    ) {
        let padding = SidewaysTabMetrics.stripEndPadding
        guard !contentLengths.isEmpty,
              width > SidewaysTabMetrics.leadingInset + SidewaysTabMetrics.bandWidth
        else {
            showsLabels = false
            documentLength = max(0, viewportLength)
            tabRects = []
            hitRects = []
            contentRects = []
            return
        }
        let labelled = Self.stack(contentLengths: contentLengths)
        let fitsLabels = Self.extent(of: labelled) + 2 * padding <= viewportLength
        let stacked = fitsLabels ? labelled : Self.stack(
            contentLengths: Array(repeating: SidewaysTabMetrics.iconOnlyLength, count: contentLengths.count)
        )
        showsLabels = fitsLabels
        let extent = Self.extent(of: stacked)
        let shift = firstTabTop.map { min(max(0, $0 - padding), max(0, viewportLength - 2 * padding - extent)) } ?? 0
        documentLength = max(viewportLength, extent + 2 * padding + shift)
        let x = SidewaysTabMetrics.leadingInset
        let tabWidth = width - x - SidewaysTabMetrics.bandWidth
        let top = padding + shift
        let rects = stacked.map { CGRect(x: x, y: top + $0.start, width: tabWidth, height: $0.length) }
        tabRects = rects
        contentRects = stacked.map {
            CGRect(x: x, y: top + $0.visibleStart, width: tabWidth, height: $0.content)
        }
        var hits = stacked.map { CGRect(x: x, y: top + $0.visibleStart, width: tabWidth, height: $0.visible) }
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

    private struct StackedTab {
        let start: CGFloat
        let length: CGFloat
        let visibleStart: CGFloat
        let visible: CGFloat
        let content: CGFloat
    }

    private static func stack(contentLengths: [CGFloat]) -> [StackedTab] {
        var result: [StackedTab] = []
        var visibleStart: CGFloat = 0
        for (index, length) in contentLengths.enumerated() {
            let content = min(SidewaysTabMetrics.maximumContentLength, length)
            let hidden = index == 0 ? 0 : SidewaysTabMetrics.overlap
            let room = index == contentLengths.count - 1 ? 0 : SidewaysTabMetrics.overlap
            let visible = content + room
            result.append(StackedTab(
                start: visibleStart - hidden, length: visible + hidden,
                visibleStart: visibleStart, visible: visible, content: content
            ))
            visibleStart += visible
        }
        return result
    }

    private static func extent(of stack: [StackedTab]) -> CGFloat {
        stack.last.map { $0.start + $0.length } ?? 0
    }

    static func fittedHeight(tabCount: Int, availableHeight: CGFloat) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let usable = availableHeight - 2 * SidewaysTabMetrics.windowCornerAllowance
        guard usable >= SidewaysTabMetrics.iconOnlyLength + 2 * SidewaysTabMetrics.stripEndPadding else { return 0 }
        return usable
    }
}
