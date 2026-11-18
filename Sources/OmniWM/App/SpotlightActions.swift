// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppIntents
import CoreSpotlight
import Foundation

struct OmniWMSettingEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Settings")
    static let defaultQuery = OmniWMSettingQuery()
    static let all = SettingsSearchIndex.entries.map(OmniWMSettingEntity.init)

    let id: String
    let entry: SettingsSearchEntry

    init(entry: SettingsSearchEntry) {
        id = entry.id
        self.entry = entry
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: entry.title),
            subtitle: LocalizedStringResource(stringLiteral: entry.context)
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = entry.keywords
        attributes.contentDescription = entry.context
        return attributes
    }
}

struct OmniWMSettingQuery: EnumerableEntityQuery {
    func entities(for identifiers: [String]) -> [OmniWMSettingEntity] {
        OmniWMSettingEntity.all.filter { identifiers.contains($0.id) }
    }

    func allEntities() -> [OmniWMSettingEntity] {
        OmniWMSettingEntity.all
    }
}

struct OpenOmniWMSettingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Settings"

    @Parameter(title: "Settings")
    var target: OmniWMSettingEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = await SpotlightActionRunner.startedController()
        SettingsWindowController.shared.show(
            settings: controller.settings,
            controller: controller,
            route: target.entry.route
        )
        return .result()
    }
}
