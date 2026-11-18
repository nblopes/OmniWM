// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class SpotlightActionsTests: XCTestCase {
    func testEverySettingHasItsOwnId() {
        let ids = OmniWMSettingEntity.all.map(\.id)

        XCTAssertEqual(ids.count, SettingsSearchIndex.entries.count)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSettingsOpenWithoutAccessibility() async {
        let controller = makeController()
        let bootstrap = install(controller)
        controller.updateAccessibilityPermissionGranted(false)

        let started = await SpotlightActionRunner.startedController()
        XCTAssertTrue(started === controller)
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
