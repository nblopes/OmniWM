// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppIntents
import AppKit
import CoreSpotlight
import Foundation

struct ToggleOverviewIntent: AppIntent {
    static let title = LocalizedStringResource(
        "command.presentation.overview",
        defaultValue: "Toggle Overview",
        table: "Commands"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        try await SpotlightActionRunner.run(.presentation(.overview))
        return .result()
    }
}

struct ToggleFullscreenIntent: AppIntent {
    static let title = LocalizedStringResource(
        "command.fullscreen.toggle",
        defaultValue: "Toggle OmniWM Fullscreen",
        table: "Commands"
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        try await SpotlightActionRunner.run(.fullscreen(.managed))
        return .result()
    }
}

struct SwitchToWorkspaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Workspace"
    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$workspace)")
    }

    @Parameter(title: "Workspace")
    var workspace: OmniWMWorkspaceEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let workspace else { throw SpotlightActionError.notFound }
        let controller = try await SpotlightActionRunner.readyControllerOutsideOverview()
        guard controller.workspaceManager.workspaceId(for: workspace.id, createIfMissing: false) != nil else {
            throw SpotlightActionError.workspaceGone(workspace.name)
        }
        try SpotlightActionError.check(IPCCommandRouter.focusWorkspace(
            rawWorkspaceID: workspace.id,
            controller: controller
        ))
        return .result()
    }
}

struct SummonWindowRightIntent: AppIntent {
    static let title: LocalizedStringResource = "Summon Window to the Right"
    static var parameterSummary: some ParameterSummary {
        Summary("Summon \(\.$window) to the right")
    }

    @Parameter(title: "Window")
    var window: OmniWMWindowEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let window else { throw SpotlightActionError.notFound }
        let controller = try await SpotlightActionRunner.readyControllerOutsideOverview()
        guard let token = OmniWMWindowEntity.token(from: window.id),
              controller.workspaceManager.handle(for: token) != nil
        else { throw SpotlightActionError.windowGone }
        if controller.workspaceManager.isAppHidden(pid: token.pid) {
            try await SpotlightAppSummoner.show(pid: token.pid, controller: controller)
        }
        guard let handle = controller.workspaceManager.handle(for: token) else { throw SpotlightActionError.windowGone }
        try SpotlightActionError.check(controller.windowActionHandler.summonWindowRightOutcome(handle: handle))
        return .result()
    }
}

struct SummonAppRightIntent: AppIntent {
    static let title: LocalizedStringResource = "Summon App to the Right"
    static var parameterSummary: some ParameterSummary {
        Summary("Summon \(\.$app) to the right")
    }

    @Parameter(title: "App")
    var app: OmniWMAppEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app else { throw SpotlightActionError.notFound }
        let controller = try await SpotlightActionRunner.readyControllerOutsideOverview()
        guard let application = await OmniWMAppQuery.loadedCatalog().application(id: app.id) else {
            throw SpotlightActionError.notFound
        }
        try await SpotlightAppSummoner.summon(application, controller: controller)
        return .result()
    }
}

struct OmniWMAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Application")
    static let defaultQuery = OmniWMAppQuery()

    let id: String
    let name: String
    let icon: Data?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            image: icon.map { DisplayRepresentation.Image(data: $0) }
        )
    }
}

struct OmniWMAppQuery: EntityStringQuery {
    private static let resultLimit = 30

    @MainActor
    func entities(for identifiers: [String]) async -> [OmniWMAppEntity] {
        let catalog = await Self.loadedCatalog()
        return await Self.entities(identifiers.compactMap(catalog.application(id:)))
    }

    @MainActor
    func entities(matching string: String) async -> [OmniWMAppEntity] {
        let catalog = await Self.loadedCatalog()
        let settings = await SpotlightActionRunner.startedController().settings
        let best = await catalog.bestMatch(
            for: string,
            language: CommandPaletteKeyboardLanguage.current(),
            shortcutTarget: settings.launcherShortcutTarget(for: string),
            launchesFor: { settings.launcherLaunches(for: $0) }
        )
        return await Self.entities(best.map { [$0] } ?? [])
    }

    @MainActor
    func suggestedEntities() async -> [OmniWMAppEntity] {
        let running = RunningApplications.current
        return await Self.entities(Self.loadedCatalog().applications(
            where: { running.processIdentifier(for: $0) != nil },
            limit: Self.resultLimit
        ))
    }

    @MainActor
    static func loadedCatalog() async -> ApplicationCatalogService {
        let catalog = ApplicationCatalogService.shared
        if !catalog.hasLoadedCatalog {
            let controller = await SpotlightActionRunner.startedController()
            catalog.refreshIfNeeded(extraFolders: controller.settings.launcher.appFolders)
        }
        while !catalog.hasLoadedCatalog {
            await StateChangeWaiters.shared.next()
        }
        return catalog
    }

    @MainActor
    private static func entities(_ applications: [LauncherApplicationResult]) async -> [OmniWMAppEntity] {
        let icons = await SpotlightActionRunner.icons(at: applications.map(\.bundleURL))
        return applications.map { OmniWMAppEntity(id: $0.id, name: $0.displayName, icon: icons[$0.bundleURL]) }
    }
}

struct OmniWMWorkspaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
    static let defaultQuery = OmniWMWorkspaceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct OmniWMWorkspaceQuery: EnumerableEntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [OmniWMWorkspaceEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func allEntities() async throws -> [OmniWMWorkspaceEntity] {
        let controller = try await SpotlightActionRunner.readyController()
        return IPCQuerySelection.orderedWorkspaces(controller: controller).map {
            OmniWMWorkspaceEntity(id: $0.name, name: controller.settings.workspaces.displayName(for: $0.name))
        }
    }
}

struct OmniWMWindowEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Window")
    static let defaultQuery = OmniWMWindowQuery()

    let id: String
    let appName: String
    let title: String
    let icon: Data?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: appName),
            subtitle: LocalizedStringResource(stringLiteral: title),
            image: icon.map { DisplayRepresentation.Image(data: $0) }
        )
    }

    static func id(for token: WindowToken) -> String {
        "\(token.pid):\(token.windowId)"
    }

    static func token(from id: String) -> WindowToken? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let pid = pid_t(parts[0]), let windowId = Int(parts[1]) else { return nil }
        return WindowToken(pid: pid, windowId: windowId)
    }
}

struct OmniWMWindowQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [OmniWMWindowEntity] {
        try await Self.entities { identifiers.contains(OmniWMWindowEntity.id(for: $0.id)) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [OmniWMWindowEntity] {
        try await Array(Self.entities(matching: string) { _ in true }.prefix(1))
    }

    @MainActor
    func suggestedEntities() async throws -> [OmniWMWindowEntity] {
        try await Self.entities { _ in true }
    }

    @MainActor
    private static func entities(
        matching query: String = "",
        where isIncluded: (CommandPaletteWindowItem) -> Bool
    ) async throws -> [OmniWMWindowEntity] {
        let controller = try await SpotlightActionRunner.readyController()
        let tiled = CommandPaletteSearch.buildWindowItems(from: controller).filter {
            isIncluded($0) && controller.workspaceManager.entry(for: $0.id)?.mode == .tiling
        }
        let items = CommandPaletteSearch.filterWindowItems(tiled, query: query)
        let appURLs = Dictionary(
            Set(items.map(\.id.pid)).compactMap { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleURL.map { (pid, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let icons = await SpotlightActionRunner.icons(at: Array(appURLs.values))
        return items.map { item in
            OmniWMWindowEntity(
                id: OmniWMWindowEntity.id(for: item.id),
                appName: item.appName,
                title: item.title,
                icon: appURLs[item.id.pid].flatMap { icons[$0] }
            )
        }
    }
}

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

enum SpotlightActionError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case accessibilityMissing
    case disabled
    case overviewOpen
    case wrongLayout
    case featureDisabled
    case noFocusedWindow
    case sameWindow
    case windowGone
    case workspaceGone(String)
    case notFound
    case failed

    static func check(_ result: ExternalCommandResult) throws {
        switch result {
        case .executed,
             .noChange:
            return
        case .ignoredDisabled: throw Self.disabled
        case .ignoredOverview: throw Self.overviewOpen
        case .ignoredLayoutMismatch: throw Self.wrongLayout
        default: throw Self.failed
        }
    }

    static func check(_ outcome: WindowSummonRightOutcome) throws {
        switch outcome {
        case .summoned,
             .movedToWorkspace:
            return
        case .noAnchor: throw Self.noFocusedWindow
        case .selfSummon: throw Self.sameWindow
        case .staleTarget: throw Self.windowGone
        case .unsupportedLayout: throw Self.wrongLayout
        case .hiddenTarget,
             .moveFailed,
             .actionFailed:
            throw Self.failed
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .accessibilityMissing: "OmniWM needs Accessibility access to observe and manage windows."
        case .disabled: "OmniWM is disabled."
        case .overviewOpen: "The command is unavailable while Overview is open."
        case .wrongLayout: "The command is unavailable for the current layout."
        case .featureDisabled: "This feature is disabled."
        case .noFocusedWindow: "Focus a window first, to summon beside it."
        case .sameWindow: "A window can't be summoned beside itself."
        case .windowGone: "The target window is no longer available."
        case let .workspaceGone(name): "Workspace \"\(name)\" no longer exists. Pick another."
        case .notFound: "Not found"
        case .failed: "The command could not be completed."
        }
    }
}
