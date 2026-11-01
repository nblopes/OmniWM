// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

extension WMController {
    func configureStackRails() {
        stackRailManager.onDrag = { [weak self] drag in
            self?.mouseEventHandler.handleStackRailDrag(drag)
        }
        stackRailManager.onRevealChanged = { [weak self] in
            self?.refreshStackRails()
        }
        stackRailManager.isHeld = { [weak self] rawFlags in
            guard let self, settings.niri.naturalWindowDrag else { return false }
            return MouseEventHandler.mouseMoveModifiersMatch(
                CGEventFlags(rawValue: rawFlags),
                required: settings.niri.naturalWindowDragModifier.cgEventFlags
            )
        }
    }

    func syncStackRailMonitor() {
        guard hasStartedServices, settings.niri.naturalWindowDrag else {
            stackRailManager.stop()
            return
        }
        stackRailManager.start()
    }

    func refreshStackRails() {
        guard stackRailManager.isRevealed, !mouseEventHandler.isLiveColumnDragActive else {
            stackRailManager.update([])
            return
        }
        stackRailManager.update(niriLayoutHandler.desiredStackRails())
    }
}
