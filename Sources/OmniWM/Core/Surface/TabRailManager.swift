// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
final class TabRailManager {
    typealias SelectionHandler = (TabRailInfo, Int, WindowToken?) -> Void

    var onSelect: SelectionHandler?
    var ringOrderedAbove: (@MainActor (UInt32) -> UInt32?)?
    var onDrag: ((TabRailDrag) -> Void)?
    var acceptsDrags: () -> Bool = { false }

    private var railWindows: [TabRailKey: TabRailWindow] = [:]
    private var railInfos: [TabRailKey: TabRailInfo] = [:]
    private var reconciledInfos: [TabRailKey: TabRailInfo] = [:]
    private var pulledTabTop: (token: WindowToken, top: CGFloat)?

    func notePulledTab(_ token: WindowToken, top: CGFloat) {
        pulledTabTop = (token, top)
    }

    func pulledTabTop(for token: WindowToken) -> CGFloat? {
        pulledTabTop?.token == token ? pulledTabTop?.top : nil
    }

    private let motionPolicy: MotionPolicy
    private let appInfoCache: AppInfoCache
    private var style: TabRailStyle = .compact

    init(motionPolicy: MotionPolicy = MotionPolicy(), appInfoCache: AppInfoCache = AppInfoCache()) {
        self.motionPolicy = motionPolicy
        self.appInfoCache = appInfoCache
    }

    func updateRails(_ infos: [TabRailInfo], forceOrdering: Bool = false, style: TabRailStyle = .compact) {
        self.style = style
        var desiredKeys = Set<TabRailKey>()
        desiredKeys.reserveCapacity(infos.count)
        for info in infos where info.tabCount > 0 {
            desiredKeys.insert(info.key)
            let isReplay = forceOrdering && reconciledInfos[info.key] == info
            reconciledInfos[info.key] = info
            if isReplay, let window = railWindows[info.key] {
                window.reorder()
                continue
            }
            railInfos[info.key] = info
            if railWindows[info.key] != nil || Self.isRenderable(visibleTileFrame: info.visibleTileFrame) {
                updateRail(info, forceOrdering: forceOrdering)
            }
        }

        let staleWindowKeys = railWindows.keys.filter { !desiredKeys.contains($0) }
        for key in staleWindowKeys {
            railWindows.removeValue(forKey: key)?.close()
        }
        let staleInfoKeys = railInfos.keys.filter { !desiredKeys.contains($0) }
        for key in staleInfoKeys {
            railInfos.removeValue(forKey: key)
        }
        reconciledInfos = reconciledInfos.filter { desiredKeys.contains($0.key) }
    }

    func applyAnimationGeometry(
        _ commands: [TabRailGeometryCommand],
        in workspaceId: WorkspaceDescriptor.ID? = nil
    ) {
        for command in commands {
            if let workspaceId, command.key.workspaceId != workspaceId {
                continue
            }
            if let window = railWindows[command.key] {
                window.updateAnimationGeometry(command)
                if let info = railInfos[command.key] {
                    railInfos[command.key] = info.presenting(command)
                }
                continue
            }
            guard Self.isRenderable(visibleTileFrame: command.visibleTileFrame),
                  let info = railInfos[command.key]
            else {
                continue
            }
            let presentedInfo = info.presenting(command)
            railInfos[command.key] = presentedInfo
            updateRail(presentedInfo, forceOrdering: false)
        }
    }

    func existingWindow(for key: TabRailKey) -> NSWindow? {
        railWindows[key]
    }

    private func updateRail(_ info: TabRailInfo, forceOrdering: Bool) {
        let key = info.key
        let window = railWindows[key] ?? {
            let window = TabRailWindow(
                owner: info.owner, workspaceId: info.workspaceId, motionPolicy: motionPolicy, appInfoCache: appInfoCache
            )
            window.onSelect = { [weak self] info, visualIndex, token in
                self?.onSelect?(info, visualIndex, token)
            }
            window.ringOrderedAbove = { [weak self] in self?.ringOrderedAbove?($0) }
            window.onDrag = { [weak self] drag in
                if let token = drag.token, let top = drag.tabTop {
                    self?.notePulledTab(token, top: top)
                }
                self?.onDrag?(drag)
            }
            window.acceptsDrags = { [weak self] in self?.acceptsDrags() ?? false }
            railWindows[key] = window
            return window
        }()
        window.update(info: info, forceOrdering: forceOrdering, style: style)
    }

    func removeAll() {
        for (_, window) in railWindows {
            window.close()
        }
        railWindows.removeAll()
        railInfos.removeAll()
        reconciledInfos.removeAll()
    }

    static func isRenderable(visibleTileFrame: CGRect) -> Bool {
        !visibleTileFrame.isNull
            && visibleTileFrame.width >= TabRailMetrics.minVisibleIntersection
            && visibleTileFrame.height >= TabRailMetrics.minVisibleIntersection
    }
}

private extension TabRailInfo {
    func presenting(_ command: TabRailGeometryCommand) -> TabRailInfo {
        TabRailInfo(
            workspaceId: workspaceId,
            owner: owner,
            plannedSeq: plannedSeq,
            tileFrame: command.tileFrame,
            visibleTileFrame: command.visibleTileFrame,
            tabCount: tabCount,
            activeVisualIndex: activeVisualIndex,
            activeWindowId: activeWindowId,
            tabs: tabs,
            orderingWindowId: command.orderingWindowId,
            displayFrame: command.displayFrame,
            travellingTabTop: travellingTabTop
        )
    }
}
