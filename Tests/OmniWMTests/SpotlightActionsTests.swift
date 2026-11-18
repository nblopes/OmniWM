// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class SpotlightActionsTests: XCTestCase {
    func testOverviewTurnedOffInSettingsIsReportedBeforeRunning() {
        let controller = makeController()
        controller.settings.overview.enabled = false

        XCTAssertEqual(
            SpotlightActionRunner.failure(before: .presentation(.overview), controller: controller),
            .featureDisabled
        )
        XCTAssertNil(SpotlightActionRunner.failure(before: .fullscreen(.managed), controller: controller))
    }

    func testRunningAppsAreMatchedByBundleOrIdentifier() {
        let byURL = LauncherApplicationResult(
            bundleURL: URL(fileURLWithPath: "/Applications/ByURL.app"),
            bundleIdentifier: nil,
            displayName: "By URL"
        )
        let byIdentifier = LauncherApplicationResult(
            bundleURL: URL(fileURLWithPath: "/Applications/Elsewhere.app"),
            bundleIdentifier: "com.example.by-identifier",
            displayName: "By Identifier"
        )
        let stopped = LauncherApplicationResult(
            bundleURL: URL(fileURLWithPath: "/Applications/Stopped.app"),
            bundleIdentifier: "com.example.stopped",
            displayName: "Stopped"
        )

        let running = RunningApplications(
            byURL: [URL(fileURLWithPath: "/Applications/ByURL.app"): 11],
            byIdentifier: ["com.example.by-identifier": 22]
        )

        XCTAssertEqual([byURL, byIdentifier, stopped].map(running.processIdentifier(for:)), [11, 22, nil])
    }

    func testSwitchingToAWorkspaceThatIsGoneSaysSo() async {
        let controller = makeController()
        let bootstrap = install(controller)
        controller.updateAccessibilityPermissionGranted(true)
        controller.isEnabled = true
        controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = true
        let intent = SwitchToWorkspaceIntent()
        intent.workspace = OmniWMWorkspaceEntity(id: "gone-\(UUID().uuidString)", name: "Gone")

        do {
            _ = try await intent.perform()
            XCTFail("Expected workspaceGone")
        } catch {
            XCTAssertEqual(error as? SpotlightActionError, .workspaceGone("Gone"))
        }
        withExtendedLifetime(bootstrap) {}
    }

    func testAnUnknownWorkspaceNameSaysSo() async {
        do {
            _ = try await SwitchToWorkspaceIntent().perform()
            XCTFail("Expected notFound")
        } catch {
            XCTAssertEqual(error as? SpotlightActionError, .notFound)
        }
    }

    func testEverySettingHasItsOwnId() {
        let ids = OmniWMSettingEntity.all.map(\.id)

        XCTAssertEqual(ids.count, SettingsSearchIndex.entries.count)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testWithoutAccessibilitySettingsOpenButActionsStop() async throws {
        let controller = makeController()
        let bootstrap = install(controller)
        controller.updateAccessibilityPermissionGranted(false)

        let started = await SpotlightActionRunner.startedController()
        XCTAssertTrue(started === controller)
        await assertReadyControllerThrows(.accessibilityMissing)
        withExtendedLifetime(bootstrap) {}
    }

    func testStartupStopsAtOnceWhenOmniWMIsDisabled() async {
        let controller = makeController()
        let bootstrap = install(controller)
        controller.updateAccessibilityPermissionGranted(true)
        controller.isEnabled = false

        await assertReadyControllerThrows(.disabled)
        withExtendedLifetime(bootstrap) {}
    }

    func testStartupRunsOnceTheFirstLayoutRefreshCompletes() async throws {
        let controller = makeController()
        let bootstrap = install(controller)
        controller.updateAccessibilityPermissionGranted(true)
        controller.isEnabled = true
        controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = false

        let ready = Task { try await SpotlightActionRunner.readyController() }
        controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = true
        StateChangeWaiters.shared.signal()

        let readyController = try await ready.value
        XCTAssertTrue(readyController === controller)
        withExtendedLifetime(bootstrap) {}
    }

    private func install(_ controller: WMController) -> AppBootstrapState {
        let bootstrap = AppBootstrapState()
        bootstrap.controller = controller
        AppDelegate.sharedBootstrap = bootstrap
        addTeardownBlock { @MainActor in
            AppDelegate.sharedBootstrap = nil
        }
        return bootstrap
    }

    private func assertReadyControllerThrows(
        _ expected: SpotlightActionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await SpotlightActionRunner.readyController()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SpotlightActionError, expected, file: file, line: line)
        }
    }

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMSpotlightActionsTests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        addTeardownBlock { @MainActor in
            controller.hasStartedServices = false
            controller.workspaceBarManager.cleanup()
            controller.layoutRefreshController.resetState()
            controller.mouseEventHandler.cleanup()
            controller.surfaceReconciler.cleanup()
            controller.axManager.cleanup()
            await controller.workspaceBarManager.flushShellForQuit()
            try FileManager.default.removeItem(at: root)
        }
        return controller
    }
}
