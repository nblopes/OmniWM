// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension NiriLayoutHandler {
    enum SidewaysRailMotion {
        case resting
        case animating([WindowToken: CGRect])
        case windowMoved(WindowToken, CGRect)
    }

    struct SidewaysRailTarget {
        let token: WindowToken
        let entry: WindowState
        let window: NiriWindow?
        let isDragged: Bool
        let isVertical: Bool
    }

    static func isBeingMoved(
        _ drag: MouseInputState.NativeTitleBarDrag?,
        token: WindowToken,
        countsCurrentFrameChange: Bool
    ) -> Bool {
        guard let drag, drag.token == token, drag.phase != .armed else { return false }
        return drag.receivedFrameChange || countsCurrentFrameChange
    }

    static func liveWindowFrames(of entries: [WindowState]) -> [WindowToken: CGRect] {
        let ids = entries.compactMap { UInt32(exactly: $0.windowId) }
        guard !ids.isEmpty else { return [:] }
        let bounds = SkyLight.shared.getWindowBounds(ids)
        var frames: [WindowToken: CGRect] = [:]
        for entry in entries {
            guard let id = UInt32(exactly: entry.windowId), let frame = bounds[id] else { continue }
            frames[entry.token] = ScreenCoordinateSpace.toAppKit(rect: frame)
        }
        return frames
    }

    func followSidewaysRails(movedWindow token: WindowToken, frame: CGRect) {
        guard let controller, controller.tabRailStyle == .sidewaysTabs, let engine = controller.niriEngine,
              let workspaceId = controller.workspaceManager.entry(for: token)?.workspaceId
        else { return }
        if sidewaysPulledTab(engine: engine, workspaceId: workspaceId)?.token == token {
            if let command = sidewaysPulledTabCommand(engine: engine, workspaceId: workspaceId) {
                controller.tabRailManager.applyAnimationGeometry([command])
            }
            return
        }
        guard
            let monitor = controller.workspaceManager.monitor(for: workspaceId),
            controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id == workspaceId,
            controller.workspaceManager.activeLayoutKind(for: workspaceId) == .niri,
            let node = engine.findNode(for: token, in: workspaceId),
            let column = engine.findColumn(containing: node, in: workspaceId), column.isTabbed,
            column.windowNodes.count > 1,
            let target = sidewaysRailTarget(engine: engine, column: column, workspaceId: workspaceId),
            target.token == token
        else { return }
        let vertical = engine.monitor(for: monitor.id)?.orientation == .vertical
        guard !vertical || controller.niriEdgePictures.presentation(for: token) == nil,
              let command = sidewaysRailCommand(
                  target: target, column: column, workspaceId: workspaceId, visibleFrame: monitor.visibleFrame,
                  motion: .windowMoved(token, frame), followsDrift: !vertical
              )
        else { return }
        controller.tabRailManager.applyAnimationGeometry([command])
    }

    func sidewaysPulledTabCommand(
        engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) -> TabRailGeometryCommand? {
        guard let controller, controller.tabRailStyle == .sidewaysTabs,
              let pulled = sidewaysPulledTab(engine: engine, workspaceId: workspaceId),
              let entry = controller.workspaceManager.entry(for: pulled.token)
        else { return nil }
        let key = TabRailKey(workspaceId: workspaceId, owner: .niriColumn(pulled.windowId))
        guard let window = Self.usableFrame(pulled.frame) else {
            return TabRailGeometryCommand(key: key, tileFrame: .zero, visibleTileFrame: .null)
        }
        let reserved = TabRailStyle.sidewaysTabs.reservedWidth
        let tile = CGRect(
            x: window.minX - reserved,
            y: window.minY,
            width: window.width + reserved,
            height: window.height
        )
        return TabRailGeometryCommand(
            key: key,
            tileFrame: tile,
            visibleTileFrame: tile,
            orderingWindowId: entry.windowId
        )
    }

    func sidewaysPulledTabInfo(engine: NiriLayoutEngine, workspaceId: WorkspaceDescriptor.ID) -> TabRailInfo? {
        guard let controller,
              let pulled = sidewaysPulledTab(engine: engine, workspaceId: workspaceId),
              let command = sidewaysPulledTabCommand(engine: engine, workspaceId: workspaceId),
              let node = engine.findNode(for: pulled.token, in: workspaceId),
              let entry = controller.workspaceManager.entry(for: pulled.token)
        else { return nil }
        return TabRailInfo(
            workspaceId: workspaceId,
            owner: command.key.owner,
            plannedSeq: controller.workspaceManager.worldSeq,
            tileFrame: command.tileFrame,
            visibleTileFrame: command.visibleTileFrame,
            tabCount: 1,
            activeVisualIndex: 0,
            activeWindowId: entry.windowId,
            tabs: tabbedColumnTabs(windows: [node], activeVisualIndex: 0, controller: controller),
            orderingWindowId: command.orderingWindowId,
            travellingTabTop: controller.tabRailManager.pulledTabTop(for: pulled.token) ?? 0
        )
    }

    func sidewaysRailCommand(
        engine: NiriLayoutEngine,
        column: NiriContainer,
        workspaceId: WorkspaceDescriptor.ID,
        visibleFrame: CGRect,
        motion: SidewaysRailMotion,
        followsDrift: Bool
    ) -> TabRailGeometryCommand? {
        guard let target = sidewaysRailTarget(engine: engine, column: column, workspaceId: workspaceId)
        else { return nil }
        return sidewaysRailCommand(
            target: target, column: column, workspaceId: workspaceId, visibleFrame: visibleFrame,
            motion: motion, followsDrift: followsDrift
        )
    }

    func sidewaysLiveFramesForAnimation(
        engine: NiriLayoutEngine,
        columns: [NiriContainer],
        workspaceId: WorkspaceDescriptor.ID,
        visibleFrame: CGRect
    ) -> [WindowToken: CGRect] {
        guard let controller, controller.tabRailStyle == .sidewaysTabs else { return [:] }
        let reach = visibleFrame.insetBy(dx: -TabRailStyle.sidewaysTabs.hitWidth, dy: 0)
        var entries: [WindowState] = []
        for column in columns where column.isTabbed && column.windowNodes.count > 1 {
            guard let target = sidewaysRailTarget(engine: engine, column: column, workspaceId: workspaceId)
            else { continue }
            let moving = target.isDragged
                || isSidewaysWindowMoving(target.token, countsCurrentFrameChange: false)
            if !moving {
                guard target.entry.hiddenState == nil,
                      let columnFrame = Self.sidewaysAnchor(column: column, target: target),
                      columnFrame.intersects(reach),
                      let previous = sidewaysColumnFrames[column.id], previous != columnFrame
                else { continue }
            }
            entries.append(target.entry)
        }
        guard !entries.isEmpty else { return [:] }
        return liveWindowFramesProvider(entries)
    }

    func pruneSidewaysColumnFrames(keeping columns: Set<NodeId>) {
        guard sidewaysColumnFrames.keys.contains(where: { !columns.contains($0) }) else { return }
        sidewaysColumnFrames = sidewaysColumnFrames.filter { columns.contains($0.key) }
    }

    private func sidewaysRailTarget(
        engine: NiriLayoutEngine,
        column: NiriContainer,
        workspaceId: WorkspaceDescriptor.ID
    ) -> SidewaysRailTarget? {
        guard let controller, controller.tabRailStyle == .sidewaysTabs, column.edgeHiddenFrame == nil
        else { return nil }
        let drag = sidewaysLiveDrag(of: column, engine: engine)
        let window = drag.isDragged ? nil : engine.projectedActiveWindow(in: column, workspaceId: workspaceId)
        guard let token = drag.isDragged ? drag.window : window?.token,
              let entry = controller.workspaceManager.entry(for: token)
        else { return nil }
        let isVertical = controller.workspaceManager.monitor(for: workspaceId)
            .flatMap { engine.monitor(for: $0.id)?.orientation } == .vertical
        return SidewaysRailTarget(
            token: token, entry: entry, window: window, isDragged: drag.isDragged, isVertical: isVertical
        )
    }

    private func sidewaysRailCommand(
        target: SidewaysRailTarget,
        column: NiriContainer,
        workspaceId: WorkspaceDescriptor.ID,
        visibleFrame: CGRect,
        motion: SidewaysRailMotion,
        followsDrift: Bool
    ) -> TabRailGeometryCommand? {
        let key = TabRailKey(workspaceId: workspaceId, owner: .niriColumn(column.id))
        if let window = target.window, window.isMaximized || window.isFullscreen {
            return TabRailGeometryCommand(key: key, tileFrame: .zero, visibleTileFrame: .null)
        }
        let movedByThisEvent = if case let .windowMoved(token, _) = motion { token == target.token } else { false }
        let moving = target.isDragged
            || isSidewaysWindowMoving(target.token, countsCurrentFrameChange: movedByThisEvent)
        if moving, let window = liveFrame(of: target, motion: motion, readsIfUnknown: true) {
            let reserved = TabRailStyle.sidewaysTabs.reservedWidth
            let tile = CGRect(
                x: window.minX - reserved, y: window.minY,
                width: window.width + reserved, height: window.height
            )
            return TabRailGeometryCommand(
                key: key, tileFrame: tile, visibleTileFrame: tile, orderingWindowId: target.entry.windowId
            )
        }
        guard !target.isDragged, let columnFrame = Self.sidewaysAnchor(column: column, target: target)
        else { return nil }
        func columnCommand(shiftedBy shift: CGFloat = 0) -> TabRailGeometryCommand {
            let frame = columnFrame.offsetBy(dx: shift, dy: 0)
            return TabRailGeometryCommand(
                key: key, tileFrame: frame, visibleTileFrame: frame.intersection(visibleFrame)
            )
        }
        let reference: CGRect
        switch motion {
        case .resting:
            sidewaysColumnFrames[column.id] = columnFrame
            return columnCommand()
        case .animating:
            reference = sidewaysColumnFrames[column.id] ?? columnFrame
            sidewaysColumnFrames[column.id] = columnFrame
        case .windowMoved:
            reference = columnFrame
        }
        guard followsDrift,
              let window = liveFrame(of: target, motion: motion, readsIfUnknown: false),
              window.intersects(reference)
        else { return columnCommand() }
        let drift = window.minX - (reference.minX + TabRailStyle.sidewaysTabs.reservedWidth)
        return abs(drift) > Self.sidewaysDriftTolerance ? columnCommand(shiftedBy: drift) : columnCommand()
    }

    private static let sidewaysDriftTolerance: CGFloat = 2

    private static func sidewaysAnchor(column: NiriContainer, target: SidewaysRailTarget) -> CGRect? {
        guard let columnFrame = usableFrame(column.renderedFrame ?? column.frame) else { return nil }
        guard !target.isVertical, let planned = usableFrame(target.window?.renderedFrame) else { return columnFrame }
        return CGRect(x: columnFrame.minX, y: planned.minY, width: columnFrame.width, height: planned.height)
    }

    private func isSidewaysWindowMoving(_ token: WindowToken, countsCurrentFrameChange: Bool) -> Bool {
        windowIsBeingMovedProvider(token, countsCurrentFrameChange)
    }

    private func liveFrame(
        of target: SidewaysRailTarget,
        motion: SidewaysRailMotion,
        readsIfUnknown: Bool
    ) -> CGRect? {
        guard target.entry.hiddenState == nil else { return nil }
        switch motion {
        case let .windowMoved(token, frame) where token == target.token:
            return Self.usableFrame(frame)
        case let .animating(frames):
            if let frame = frames[target.token] { return Self.usableFrame(frame) }
        case .resting,
             .windowMoved:
            break
        }
        guard readsIfUnknown else { return nil }
        return Self.usableFrame(liveWindowFramesProvider([target.entry])[target.token])
    }

    private static func usableFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame, !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}
