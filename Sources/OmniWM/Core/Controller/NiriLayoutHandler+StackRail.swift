// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

extension NiriLayoutHandler {
    func desiredStackRails() -> [StackRail] {
        guard let controller, let engine = controller.niriEngine else { return [] }
        var rails: [StackRail] = []
        for monitor in controller.workspaceManager.monitors {
            guard let workspace = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id),
                  controller.workspaceManager.activeLayoutKind(for: workspace.id) == .niri
            else { continue }
            for column in engine.columns(in: workspace.id)
                where !column.isTabbed && engine.projectedWindows(in: column, workspaceId: workspace.id).count > 1
            {
                guard let rendered = column.renderedFrame,
                      !rendered.isNull,
                      !rendered.isInfinite,
                      let frame = StackRail.frame(beside: rendered.intersection(monitor.visibleFrame))
                else { continue }
                rails.append(.init(columnId: column.id, workspaceId: workspace.id, frame: frame))
            }
        }
        return rails
    }
}
