// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import QuartzCore

extension NiriLayoutEngine {
    func liveStackMembers(
        of column: NiriContainer,
        grabbing window: NiriWindow,
        context: NiriInteractionContext
    ) -> [LiveColumnMove.StackMember] {
        let spans = liveWindowSpans(in: column, context: context)
        return column.windowNodes.map { node in
            let span = spans.first { $0.window === node }
            return .init(
                windowId: node.id,
                sizing: .init(size: node.size, height: node.height, restsAtTop: node.restsAtTop(of: column)),
                height: span.map { $0.maxY - $0.minY } ?? 0
            )
        }
    }

    func liveRailFrame(of move: LiveColumnMove, at time: TimeInterval = CACurrentMediaTime()) -> CGRect? {
        guard let target = move.railStart,
              let window = findNode(by: move.windowId, in: move.workspaceId) as? NiriWindow
        else { return nil }
        let offset = window.renderOffset(at: time)
        return CGRect(
            x: target.minX + offset.x + move.railDelta.dx,
            y: target.minY + offset.y + move.railDelta.dy,
            width: target.width,
            height: target.height + window.renderHeightOffset(at: time)
        )
    }

    func liveDraggedTabsFrame(_ column: NiriContainer) -> CGRect? {
        guard let move = liveColumnMove,
              move.isWholeColumn,
              column.isTabbed,
              liveDraggedColumn(for: move) === column
        else { return nil }
        guard let window = move.railStart == nil ? move.draggedFrame : liveRailFrame(of: move) else { return nil }
        let inset = tabContentInset(for: column)
        return CGRect(x: window.minX - inset, y: window.minY, width: window.width + inset, height: window.height)
    }

    func liveCarriedWindows(for move: LiveColumnMove) -> [NiriWindow] {
        guard move.isWholeStack else {
            return [findNode(by: move.windowId, in: move.workspaceId) as? NiriWindow].compactMap(\.self)
        }
        return move.stackMembers.compactMap { findNode(by: $0.windowId, in: move.workspaceId) as? NiriWindow }
    }

    func liveColumn(_ column: NiriContainer, canTake carried: [NiriWindow], context: NiriInteractionContext) -> Bool {
        guard !column.isTabbed else { return true }
        let staying = projectedWindows(in: column, workspaceId: context.workspaceId)
            .filter { node in !carried.contains { $0 === node } }
        let minimum = (staying + carried).reduce(0) { $0 + $1.constraints.normalized().minSize.height }
        let gaps = context.gaps * CGFloat(staying.count + carried.count + 1)
        return minimum + gaps <= context.workingFrame.height + 0.5
    }

    func placeLiveMerge(
        _ landing: LiveColumnMove.Landing?,
        move: inout LiveColumnMove,
        context: NiriInteractionContext,
        state: inout ViewportState
    ) -> Bool {
        let carried = liveCarriedWindows(for: move)
        guard let window = carried.first(where: { $0.id == move.windowId }),
              let home = liveDraggedColumn(for: move),
              let source = findColumn(containing: window, in: move.workspaceId)
        else { return false }
        let target = landing.flatMap { liveColumn(withId: $0.columnId, in: move.workspaceId) }
        retargetActiveColumn(to: home, context: context, state: &state)
        let columnsBefore = primaryPositions(context: context, state: state)
        let placed = slideLiveWindows(in: [source, target ?? home], skipping: carried, context: context) {
            restoreLiveMergeHeights(move.mergeHeights, in: move.workspaceId)
            move.mergeHeights = []
            let keepsHeights = target.map { liveMergeKeepsHeights($0, carrying: carried, move: move, context: context) }
            guard relocateLiveStack(carried, to: landing, from: source, move: move, context: context) else {
                return false
            }
            if let target, let keepsHeights {
                shareLiveMerge(target, carrying: carried, keepingHeights: keepsHeights, move: &move)
            }
            keepLiveColumnWidths(landing: landing != nil, move: &move)
            return true
        }
        guard placed else { return false }
        move.landing = landing
        animateLiveColumnChange(from: columnsBefore, anchoredOn: home, context: context, state: &state)
        return true
    }

    func restoreLiveMergeHeights(_ heights: [LiveColumnMove.MateHeight], in workspaceId: WorkspaceDescriptor.ID) {
        for saved in heights {
            if let mate = findNode(by: saved.windowId, in: workspaceId) as? NiriWindow {
                saved.apply(to: mate)
            }
        }
    }

    private func liveMergeKeepsHeights(
        _ target: NiriContainer,
        carrying carried: [NiriWindow],
        move: LiveColumnMove,
        context: NiriInteractionContext
    ) -> Bool {
        guard !target.isTabbed else { return true }
        let staying = liveWindowSpans(in: target, context: context)
            .filter { span in !carried.contains { $0 === span.window } }
        let used = staying.reduce(0) { $0 + $1.maxY - $1.minY }
        let free = context.workingFrame.height - context.gaps * CGFloat(staying.count + 1) - used
        let members = move.stackMembers.filter { $0.height > 0 }
        let needed = members.reduce(0) { $0 + $1.height } + context.gaps * CGFloat(members.count)
        return free + 0.5 >= needed
    }

    private func shareLiveMerge(
        _ target: NiriContainer,
        carrying carried: [NiriWindow],
        keepingHeights: Bool,
        move: inout LiveColumnMove
    ) {
        guard !target.isTabbed else { return }
        if keepingHeights {
            for member in move.stackMembers {
                (findNode(by: member.windowId, in: move.workspaceId) as? NiriWindow)?.height = .fixed(member.height)
            }
            return
        }
        let staying = target.windowNodes.filter { node in !carried.contains { $0 === node } }
        move.mergeHeights = staying.map {
            .init(windowId: $0.id, height: $0.height, restsAtTop: $0.restsAtTop(of: target))
        }
        for node in target.windowNodes {
            node.height = .default
        }
    }

    private func relocateLiveStack(
        _ carried: [NiriWindow],
        to landing: LiveColumnMove.Landing?,
        from source: NiriContainer,
        move: LiveColumnMove,
        context: NiriInteractionContext
    ) -> Bool {
        guard let home = liveDraggedColumn(for: move) else { return false }
        let sourceActive = source !== home && source.isTabbed
            ? projectedActiveWindow(in: source, workspaceId: move.workspaceId)
            : nil
        if let landing, let target = liveColumn(withId: landing.columnId, in: move.workspaceId) {
            guard insertLiveMerge(carried, at: landing, in: target, home: home, context: context) else {
                return false
            }
        } else {
            returnLiveStackHome(carried, to: home, move: move)
        }
        if let sourceActive, sourceActive.parent === source {
            activateWindow(sourceActive.id, in: move.workspaceId)
            source.cachedWidth = 0
        }
        return true
    }

    private func insertLiveMerge(
        _ carried: [NiriWindow],
        at landing: LiveColumnMove.Landing,
        in column: NiriContainer,
        home: NiriContainer,
        context: NiriInteractionContext
    ) -> Bool {
        guard var beside = findNode(by: landing.targetWindowId, in: context.workspaceId) as? NiriWindow
        else { return false }
        let homeWidth = home.cachedWidth
        let shownTab = column.isTabbed ? projectedActiveWindow(in: column, workspaceId: context.workspaceId) : nil
        var position: InsertPosition = !column.isTabbed && landing.above ? .after : .before
        for window in carried {
            guard stackWindow(
                window,
                beside: beside,
                position: position,
                removingEmptySource: false,
                in: context.workspaceId,
                geometry: context.sizingGeometry
            ) else { return false }
            beside = window
            position = .after
        }
        if let shownTab, shownTab.parent === column {
            activateWindow(shownTab.id, in: context.workspaceId)
            column.cachedWidth = 0
        } else {
            carried.forEach { $0.isHiddenInTabbedMode = false }
        }
        if home.windowNodes.isEmpty, !home.isLiveHomeSpot {
            home.isLiveHomeSpot = true
            home.width = .fixed(homeWidth)
            home.cachedWidth = 0
        }
        return true
    }

    private func returnLiveStackHome(_ carried: [NiriWindow], to home: NiriContainer, move: LiveColumnMove) {
        for (index, window) in carried.enumerated() {
            if let source = window.parent as? NiriContainer, source !== home, source.isTabbed {
                source.cachedWidth = 0
            }
            home.insertChild(window, at: index)
            move.stackMembers.first { $0.windowId == window.id }?.sizing.apply(to: window)
        }
        if let shown = home.windowNodes.firstIndex(where: { $0.id == move.windowId }) {
            home.setActiveTileIdx(shown)
        }
        updateTabbedColumnVisibility(column: home)
        home.cachedWidth = 0
        guard move.homeColumnId == move.originalSlot.columnId else { return }
        home.isLiveHomeSpot = false
        restoreLiveSizing(move.ownSizing, to: home)
    }
}
