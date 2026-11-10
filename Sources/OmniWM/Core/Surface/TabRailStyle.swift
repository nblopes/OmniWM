// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

enum TabRailStyle: String, CaseIterable, Codable, Equatable {
    case compact
    case appIcons
    case sidewaysTabs

    static let iconSize: CGFloat = 20
    static let iconRowHeight: CGFloat = 28

    var reservedWidth: CGFloat {
        switch self {
        case .compact: TabRailMetrics.totalWidth
        case .appIcons: 28
        case .sidewaysTabs: SidewaysTabMetrics.stripWidth
        }
    }

    var hitWidth: CGFloat {
        max(reservedWidth, TabRailMetrics.hitWidth)
    }

    var followsWholeTile: Bool {
        self == .sidewaysTabs
    }

    var windowOverlap: CGFloat {
        self == .sidewaysTabs ? SidewaysTabMetrics.tuckUnderWindow : 0
    }

    var localizedDisplayName: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .appIcons: String(localized: "App icons")
        case .sidewaysTabs: String(localized: "Sideways tabs")
        }
    }

    func fittedHeight(tabCount: Int, availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .compact:
            TabRailLayout.fittedHeight(tabCount: tabCount, availableHeight: availableHeight)
        case .appIcons:
            min(max(0, availableHeight), CGFloat(max(0, tabCount)) * Self.iconRowHeight)
        case .sidewaysTabs:
            SidewaysTabLayout.fittedHeight(tabCount: tabCount, availableHeight: availableHeight)
        }
    }
}
