// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import os
import Synchronization

final class TabRailRenderMetricsRecorder: RuntimeTraceRecording, @unchecked Sendable {
    static let shared = TabRailRenderMetricsRecorder()

    let sectionTitle = "Tab Rail Render Metrics"

    enum UpdateCause: String, CaseIterable, Sendable {
        case tabs
        case hover
        case tuck
        case layout
        case appearance
    }

    private struct Counters {
        var passes: [UpdateCause: Int] = [:]
        var skippedUpdates = 0
        var contentRenders = 0
        var contentReuses = 0
        var renderedPointArea: UInt64 = 0
        var shapeUpdates = 0
        var fillUpdates = 0
        var orderUpdates = 0
        var windowMoves = 0
        var windowResizes = 0
    }

    private let active = Atomic<Bool>(false)
    private let counters = OSAllocatedUnfairLock(initialState: Counters())

    private func bump(_ body: @Sendable (inout Counters) -> Void) {
        guard active.load(ordering: .relaxed) else { return }
        counters.withLock { counters in
            guard active.load(ordering: .relaxed) else { return }
            body(&counters)
        }
    }

    func notePass(_ cause: UpdateCause) {
        bump { $0.passes[cause, default: 0] += 1 }
    }

    func noteSkippedUpdate() {
        bump { $0.skippedUpdates += 1 }
    }

    func noteContentRender(area: CGFloat) {
        let boundedArea = area.isFinite ? max(0, area) : 0
        bump {
            $0.contentRenders += 1
            $0.renderedPointArea += UInt64(boundedArea.rounded(.up))
        }
    }

    func noteContentReuse() {
        bump { $0.contentReuses += 1 }
    }

    func noteShapeUpdate() {
        bump { $0.shapeUpdates += 1 }
    }

    func noteFillUpdate() {
        bump { $0.fillUpdates += 1 }
    }

    func noteOrderUpdate() {
        bump { $0.orderUpdates += 1 }
    }

    func noteWindowMove() {
        bump { $0.windowMoves += 1 }
    }

    func noteWindowResize() {
        bump { $0.windowResizes += 1 }
    }

    func beginCapture() {
        counters.withLock { $0 = Counters() }
        active.store(true, ordering: .relaxed)
    }

    func endCapture() {
        active.store(false, ordering: .relaxed)
        counters.withLock { _ in }
    }

    func dump() -> String {
        let snapshot = counters.withLock { $0 }
        let passes = UpdateCause.allCases.map { "\($0.rawValue)=\(snapshot.passes[$0, default: 0])" }
        guard snapshot.passes.values.contains(where: { $0 > 0 }) || snapshot.skippedUpdates > 0
            || snapshot.windowMoves > 0 || snapshot.windowResizes > 0
        else { return "none" }
        return [
            "passes " + passes.joined(separator: " ") + " skippedUpdates=\(snapshot.skippedUpdates)",
            "contentRenders=\(snapshot.contentRenders) contentReuses=\(snapshot.contentReuses)"
                + " renderedPointArea=\(snapshot.renderedPointArea)",
            "shapeUpdates=\(snapshot.shapeUpdates) fillUpdates=\(snapshot.fillUpdates)"
                + " orderUpdates=\(snapshot.orderUpdates)",
            "windowMoves=\(snapshot.windowMoves) windowResizes=\(snapshot.windowResizes)"
        ].joined(separator: "\n")
    }
}
