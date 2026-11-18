// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreSpotlight
import Foundation

@MainActor
enum SpotlightActionRunner {
    static func startedController() async -> WMController {
        while true {
            if let controller = AppDelegate.sharedBootstrap?.controller {
                return controller
            }
            await StateChangeWaiters.shared.next()
        }
    }
}

enum SpotlightSettingsIndex {
    static func update() {
        Task {
            do {
                let index = CSSearchableIndex.default()
                try await index.deleteAppEntities(ofType: OmniWMSettingEntity.self)
                try await index.indexAppEntities(OmniWMSettingEntity.all)
            } catch {
                Log.spotlight.error("Indexing OmniWM's settings in Spotlight failed: \(error)")
            }
        }
    }
}
