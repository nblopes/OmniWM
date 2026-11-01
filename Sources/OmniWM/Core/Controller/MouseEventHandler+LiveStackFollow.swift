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

    func followLiveStack(_ entry: WindowState) {
        guard let engine = controller?.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeStack,
              move.windowToken == entry.token,
              let observed = nativeWindowFrameProvider(entry.axRef),
              let pointer = state.liveDragLocation
        else { return }
        engine.liveColumnMove?.followAnchor = .init(frame: observed, pointer: pointer)
        moveLiveStackFollowers(to: observed)
    }

    func followLiveStack(to pointer: CGPoint) {
        guard let anchor = controller?.niriEngine?.liveColumnMove?.followAnchor else { return }
        moveLiveStackFollowers(to: anchor.frame.offsetBy(
            dx: pointer.x - anchor.pointer.x,
            dy: pointer.y - anchor.pointer.y
        ))
    }

    private func moveLiveStackFollowers(to frame: CGRect) {
        guard let controller,
              let engine = controller.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeStack,
              frame != move.followFrame
        else { return }
        engine.liveColumnMove?.followFrame = frame
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .interactiveGesture,
            affectedWorkspaceIds: [move.workspaceId]
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
              let window = engine.projectedActiveWindow(in: column, workspaceId: workspaceId)
              ?? engine.projectedWindows(in: column, workspaceId: workspaceId).first
        else { return }
        finishLiveStackDrop(in: workspaceId)
        let viewport = controller.workspaceManager.niriViewportState(for: workspaceId)
        guard let startFrame = engine.liveWindowFrame(of: window, in: column, context: context, state: viewport),
              controller.workspaceManager.withNiriViewportState(for: workspaceId, { viewportState in
                  engine.liveColumnMoveBegin(
                      windowId: window.id,
                      windowToken: window.token,
                      movesStack: true,
                      context: context,
                      state: &viewportState
                  )
              })
        else { return }
        state.liveTabPull = .init(token: window.token, anchorLocation: drag.location, startFrame: startFrame)
        engine.liveColumnMove?.followAnchor = .init(frame: startFrame, pointer: drag.location)
        state.deferredClickScroll = nil
        raiseLiveStack()
        controller.refreshStackRails()
        startLiveDragKeyCapture()
        moveLiveTabPull(to: drag.location)
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
        let carried = engine.liveCarriedWindows(for: move)
        for raised in carried.filter({ $0.id != move.windowId }) + carried.filter({ $0.id == move.windowId }) {
            guard let entry = controller.workspaceManager.entry(for: raised.token) else { continue }
            controller.performWindowFronting(pid: entry.pid, windowId: entry.windowId, axRef: entry.axRef)
        }
    }
}
