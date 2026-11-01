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
                movesStack: !wantsLiveStackMode(),
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
        guard let controller,
              let engine = controller.niriEngine,
              let move = engine.liveColumnMove,
              move.isWholeStack,
              move.windowToken == entry.token,
              let observed = nativeWindowFrameProvider(entry.axRef),
              observed != move.followFrame
        else { return }
        engine.liveColumnMove?.followFrame = observed
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .interactiveGesture,
            affectedWorkspaceIds: [move.workspaceId]
        )
    }
}
