// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
final class StackRailManager {
    var onDrag: ((StackRailDrag) -> Void)?
    var onRevealChanged: (() -> Void)?
    var isHeld: (UInt64) -> Bool = { _ in false }
    private(set) var isRevealed = false
    private var windows: [NodeId: StackRailWindow] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(rawFlags: UInt64(event.modifierFlags.rawValue))
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleFlagsChanged(rawFlags: UInt64(event.modifierFlags.rawValue))
                }
            }
        }
    }

    func stop() {
        [localMonitor, globalMonitor].compactMap(\.self).forEach(NSEvent.removeMonitor)
        localMonitor = nil
        globalMonitor = nil
        isRevealed = false
        update([])
    }

    func handleFlagsChanged(rawFlags: UInt64) {
        let held = isHeld(rawFlags)
        guard held != isRevealed else { return }
        isRevealed = held
        onRevealChanged?()
    }

    func update(_ rails: [StackRail]) {
        let wanted = Dictionary(rails.map { ($0.columnId, $0) }, uniquingKeysWith: { first, _ in first })
        for (columnId, window) in windows where wanted[columnId] == nil {
            window.orderOut(nil)
            window.close()
            windows[columnId] = nil
        }
        for (columnId, rail) in wanted {
            let window = windows[columnId] ?? makeWindow(for: rail)
            windows[columnId] = window
            window.show(rail)
        }
    }

    private func makeWindow(for rail: StackRail) -> StackRailWindow {
        let window = StackRailWindow(rail: rail)
        window.onDrag = { [weak self] drag in
            self?.onDrag?(drag)
        }
        return window
    }
}
