// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreSpotlight
import Foundation

@MainActor
enum SpotlightActionRunner {
    static func run(_ command: HotkeyCommand) async throws {
        let controller = try await readyController()
        if let failure = failure(before: command, controller: controller) {
            throw failure
        }
        try SpotlightActionError.check(controller.commandHandler.performCommand(command))
    }

    static func startedController() async -> WMController {
        while true {
            if let controller = AppDelegate.sharedBootstrap?.controller {
                return controller
            }
            await StateChangeWaiters.shared.next()
        }
    }

    static func readyController() async throws -> WMController {
        while true {
            let controller = await startedController()
            guard controller.accessibilityPermissionGranted else { throw SpotlightActionError.accessibilityMissing }
            guard controller.isEnabled else { throw SpotlightActionError.disabled }
            if controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh {
                return controller
            }
            await StateChangeWaiters.shared.next()
        }
    }

    static func readyControllerOutsideOverview() async throws -> WMController {
        let controller = try await readyController()
        guard !controller.isOverviewOpen() else { throw SpotlightActionError.overviewOpen }
        return controller
    }

    static func failure(before command: HotkeyCommand, controller: WMController) -> SpotlightActionError? {
        controller.settings.isCommandFeatureEnabled(command) ? nil : .featureDisabled
    }

    static func icons(at urls: [URL]) async -> [URL: Data] {
        await LauncherIconStore.shared.applicationIconPNGs(at: urls, points: 32, scale: 2)
    }
}

@MainActor
enum SpotlightAppSummoner {
    static func summon(_ application: LauncherApplicationResult, controller: WMController) async throws {
        guard let pid = application.runningProcessIdentifier else {
            return try await open(application, preselectingRight: true, controller: controller)
        }
        if controller.workspaceManager.isAppHidden(pid: pid) {
            try await show(pid: pid, controller: controller)
        }
        guard let handle = tiledWindow(of: pid, controller: controller) else {
            return try await open(application, preselectingRight: false, controller: controller)
        }
        try SpotlightActionError.check(controller.windowActionHandler.summonWindowRightOutcome(handle: handle))
    }

    private static func tiledWindow(of pid: pid_t, controller: WMController) -> WindowHandle? {
        let workspaceManager = controller.workspaceManager
        if let recent = workspaceManager.mostRecentlyFocusedHandle(forPid: pid),
           workspaceManager.entry(for: recent.id)?.mode == .tiling
        {
            return recent
        }
        return workspaceManager.allEntries()
            .first { $0.pid == pid && $0.mode == .tiling }
            .flatMap { workspaceManager.handle(for: $0.token) }
    }

    static func show(pid: pid_t, controller: WMController) async throws {
        let reveal = StopApplicationReveal(
            isHidden: {
                MainActor.assumeIsolated {
                    NSRunningApplication(processIdentifier: pid)?.isTerminated == false
                        ? controller.workspaceManager.isAppHidden(pid: pid)
                        : nil
                }
            },
            requestUnhide: { NSRunningApplication(processIdentifier: pid)?.unhide() == true },
            observe: { changed in StateChangeWaiters.shared.observe(changed) }
        )
        let deadline = ProcessInfo.processInfo.systemUptime + IntentLedger.appRevealDeadline / .seconds(1)
        guard await reveal.reveal(deadline: deadline) else { throw SpotlightActionError.failed }
    }

    private static func open(
        _ application: LauncherApplicationResult,
        preselectingRight: Bool,
        controller: WMController
    ) async throws {
        if preselectingRight {
            _ = controller.commandHandler.performCommand(.dwindle(.preselect(.right)))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: application.bundleURL, configuration: configuration)
        } catch {
            if preselectingRight {
                _ = controller.commandHandler.performCommand(.dwindle(.preselectClear))
            }
            throw SpotlightActionError.failed
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
