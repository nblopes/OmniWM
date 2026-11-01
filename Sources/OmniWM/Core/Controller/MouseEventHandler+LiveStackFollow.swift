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
              var move = engine.liveColumnMove,
              move.isWholeStack,
              frame != move.followFrame
        else { return }
        move.followFrame = frame
        engine.liveColumnMove?.followFrame = frame
        let targets = move.stackMembers.compactMap { member -> SkyLightPositionTarget? in
            guard member.windowId != move.windowId,
                  let token = (engine.findNode(by: member.windowId, in: move.workspaceId) as? NiriWindow)?.token,
                  let followed = engine.liveFollowingFrame(for: token, move: move)
            else { return nil }
            return .init(token: token, frame: followed)
        }
        guard controller.axManager.applyPositionsViaSkyLight(targets) == .submitted else { return }
        for target in targets {
            controller.axManager.recordSkyLightMove(windowId: target.token.windowId, origin: target.frame.origin)
            controller.axManager.forceApplyNextFrame(for: target.token.windowId)
        }
    }
}
