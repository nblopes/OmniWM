// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func beginLiveColumnMove(of window: NiriWindow, entry: WindowState, engine: NiriLayoutEngine) -> Bool {
        guard let controller, let context = liveColumnContext(for: entry.workspaceId) else { return false }
        return controller.workspaceManager.withNiriViewportState(for: entry.workspaceId) { viewportState in
            engine.liveColumnMoveBegin(
                windowId: window.id,
                windowToken: entry.token,
                canCarry: hasOtherLiveStrip(than: entry.workspaceId),
                context: context,
                state: &viewportState
            )
        }
    }

    func wantsLiveStackMode() -> Bool {
        guard let controller else { return false }
        return Self.mouseMoveModifiersMatch(
            state.liveDragModifiers ?? modifierFlagsProvider(),
            required: controller.settings.niri.naturalWindowDragModifier.cgEventFlags
        )
    }

    func handleStackRailDrag(_ drag: StackRailDrag) {
        let workspaceId = drag.rail.workspaceId
        guard !isLiveColumnDragActive,
              let controller,
              controller.settings.niri.naturalWindowDrag,
              let engine = controller.niriEngine,
              let context = liveColumnContext(for: workspaceId),
              let column = engine.liveColumn(withId: drag.rail.columnId, in: workspaceId),
              !column.isTabbed,
              let window = engine.projectedWindows(in: column, workspaceId: workspaceId).last,
              let handle = controller.workspaceManager.handle(for: window.token)
        else { return }
        finishLiveStackDrop(in: workspaceId)
        let members = engine.liveStackMembers(of: column, grabbing: window, context: context)
        toggleTabbed(showing: window, handle: handle, column: column, in: workspaceId)
        guard column.isTabbed else { return }
        state.foldedStackColumnId = column.id
        guard controller.workspaceManager.withNiriViewportState(for: workspaceId, { viewportState in
            engine.liveColumnMoveBegin(
                windowId: window.id,
                windowToken: window.token,
                movesStack: true,
                context: context,
                state: &viewportState
            )
        }), let railStart = engine.liveColumnMove?.railStart
        else {
            unfoldDraggedStack(showing: window.token)
            return
        }
        engine.liveColumnMove?.stackMembers = members
        state.liveTabPull = .init(token: window.token, anchorLocation: drag.location, startFrame: railStart)
        state.deferredClickScroll = nil
        raiseLiveStack()
        controller.refreshStackRails()
        startLiveDragKeyCapture()
        moveLiveTabPull(to: drag.location)
    }

    func unfoldDraggedStack(showing token: WindowToken) {
        guard let columnId = state.foldedStackColumnId else { return }
        state.foldedStackColumnId = nil
        guard let controller,
              let engine = controller.niriEngine,
              let entry = controller.workspaceManager.entry(for: token),
              let window = engine.findNode(for: token, in: entry.workspaceId),
              let column = engine.findColumn(containing: window, in: entry.workspaceId),
              column.id == columnId,
              column.isTabbed,
              let handle = controller.workspaceManager.handle(for: token)
        else { return }
        toggleTabbed(showing: window, handle: handle, column: column, in: entry.workspaceId)
    }

    func noteWindowOrderChanged(_ windowId: UInt32) {
        guard state.liveTabPull != nil,
              state.liveStackRaise == nil,
              let engine = controller?.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeStack,
              !engine.liveCarriedWindows(for: move).contains(where: { $0.token.windowId == Int(windowId) })
        else { return }
        state.liveStackRaise = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            state.liveStackRaise = nil
            raiseLiveStack()
        }
    }

    private func raiseLiveStack() {
        guard state.liveTabPull != nil,
              let controller,
              let engine = controller.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeStack
        else { return }
        guard let entry = controller.workspaceManager.entry(for: move.windowToken) else { return }
        controller.performWindowFronting(pid: entry.pid, windowId: entry.windowId, axRef: entry.axRef)
    }

    func followDraggedTabs(_ entry: WindowState) {
        guard let controller,
              let engine = controller.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeColumn,
              move.railStart == nil,
              move.windowToken == entry.token,
              let observed = nativeWindowFrameProvider(entry.axRef),
              observed != move.draggedFrame
        else { return }
        engine.liveColumnMove?.draggedFrame = observed
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .interactiveGesture,
            affectedWorkspaceIds: [move.workspaceId]
        )
    }
}
