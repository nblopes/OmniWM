// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension NiriLayoutHandler {
    struct SidewaysLiveDrag {
        let isDragged: Bool
        let window: WindowToken?
    }

    struct SidewaysPulledTab {
        let windowId: NodeId
        let token: WindowToken
        let frame: CGRect?
    }

    func sidewaysPulledTab(engine: NiriLayoutEngine, workspaceId: WorkspaceDescriptor.ID) -> SidewaysPulledTab? {
        guard let move = engine.liveColumnMove, move.pullsTab, move.workspaceId == workspaceId else { return nil }
        return SidewaysPulledTab(windowId: move.windowId, token: move.windowToken, frame: move.floatingFrame)
    }

    func sidewaysLiveDrag(of column: NiriContainer, engine: NiriLayoutEngine) -> SidewaysLiveDrag {
        guard engine.isLiveDraggedColumn(column) else { return SidewaysLiveDrag(isDragged: false, window: nil) }
        return SidewaysLiveDrag(isDragged: true, window: engine.liveColumnMove?.windowToken)
    }
}
