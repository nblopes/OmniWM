// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func handleTabRailDrag(_ drag: TabRailDrag) {
        guard let token = drag.token,
              !isLiveColumnDragActive,
              let controller,
              controller.settings.niri.naturalWindowDrag,
              let entry = controller.workspaceManager.entry(for: token),
              controller.workspaceManager.activeLayoutKind(for: entry.workspaceId) == .niri,
              let engine = controller.niriEngine,
              let context = liveColumnContext(for: entry.workspaceId),
              let window = engine.findNode(for: token, in: entry.workspaceId),
              let column = engine.findColumn(containing: window, in: entry.workspaceId)
        else { return }
        finishLiveStackDrop(in: entry.workspaceId)
        let viewport = controller.workspaceManager.niriViewportState(for: entry.workspaceId)
        guard let startFrame = engine.liveWindowFrame(of: window, in: column, context: context, state: viewport)
            ?? nativeWindowFrameProvider(entry.axRef)
        else { return }

        let began = controller.workspaceManager.withNiriViewportState(for: entry.workspaceId) { viewportState in
            engine.liveColumnMoveBegin(
                windowId: window.id,
                windowToken: token,
                pullsTab: true,
                context: context,
                state: &viewportState
            )
        }
        guard began else { return }
        state.liveTabPull = .init(token: token, anchorLocation: drag.location, startFrame: startFrame)
        state.deferredClickScroll = nil
        startLiveDragKeyCapture()
        let detached = controller.workspaceManager.withNiriViewportState(for: entry.workspaceId) { viewportState in
            engine.liveColumnMoveDetachTab(
                towardTrailingSide: drag.location.x >= drag.pressLocation.x,
                cursor: drag.location,
                context: context,
                state: &viewportState
            )
        }
        if detached {
            engine.liveColumnMoveSettled()
        }
        moveLiveTabPull(to: drag.location)
    }

    func moveLiveTabPull(to location: CGPoint) {
        guard let pull = state.liveTabPull,
              let controller,
              let engine = controller.niriEngine,
              engine.liveColumnMove?.windowToken == pull.token
        else { return }
        let delta = CGVector(dx: location.x - pull.anchorLocation.x, dy: location.y - pull.anchorLocation.y)
        if engine.liveColumnMove?.railStart == nil {
            engine.liveColumnMove?.floatingFrame = pull.startFrame.offsetBy(dx: delta.dx, dy: delta.dy)
        } else {
            engine.liveColumnMove?.railDelta = delta
            moveDraggedTabRail()
        }
        state.liveDragLocation = location
        state.liveDragModifiers = nil
        updateLiveColumnDrag(at: location)
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .interactiveGesture,
            affectedWorkspaceIds: Set([engine.liveColumnMove?.workspaceId].compactMap(\.self))
        )
    }

    func endLiveTabPull(at location: CGPoint) {
        guard let pull = state.liveTabPull, let controller, let engine = controller.niriEngine else { return }
        moveLiveTabPull(to: location)
        let released = engine.liveColumnMove.flatMap { engine.liveFloatingFrame(for: pull.token, in: $0.workspaceId) }
        _ = finishLiveColumnDrag(token: pull.token, releaseFrame: released)
        unfoldDraggedStack(showing: pull.token)
    }
}
