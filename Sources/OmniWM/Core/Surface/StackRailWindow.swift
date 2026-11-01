// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

struct StackRail: Equatable {
    let columnId: NodeId
    let workspaceId: WorkspaceDescriptor.ID
    let frame: CGRect

    static let width: CGFloat = 16
    static let maxHeight: CGFloat = 120

    static func frame(beside column: CGRect) -> CGRect? {
        guard column.width > 1, column.height > 1 else { return nil }
        let height = min(maxHeight, column.height * 0.4)
        return CGRect(x: column.minX - width, y: column.midY - height / 2, width: width, height: height)
    }
}

struct StackRailDrag {
    let rail: StackRail
    let location: CGPoint
}

@MainActor
final class StackRailWindow: NSPanel {
    private let railView = StackRailView(frame: .zero)
    private let surfaceCoordinator = SurfaceCoordinator.shared
    private let surfaceID: String
    private(set) var rail: StackRail
    var onDrag: ((StackRailDrag) -> Void)?

    init(rail: StackRail) {
        self.rail = rail
        surfaceID = "stack-rail-\(rail.workspaceId.uuidString)-\(rail.columnId.uuid.uuidString)"
        super.init(
            contentRect: rail.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = railView
        railView.onDrag = { [weak self] location in
            guard let self else { return }
            onDrag?(StackRailDrag(rail: self.rail, location: location))
        }
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func show(_ rail: StackRail) {
        self.rail = rail
        if frame != rail.frame {
            setFrame(rail.frame, display: true)
        }
        orderFront(nil)
        guard windowNumber > 0 else { return }
        surfaceCoordinator.registerWindowNumber(
            id: surfaceID,
            windowNumber: windowNumber,
            frameProvider: { [weak self] in self?.frame },
            visibilityProvider: { [weak self] in self?.isVisible == true },
            policy: SurfacePolicy(
                kind: .tabRail,
                hitTestPolicy: .interactive,
                capturePolicy: .excluded,
                suppressesManagedFocusRecovery: false
            )
        )
    }

    override func close() {
        surfaceCoordinator.unregister(id: surfaceID)
        super.close()
    }
}

@MainActor
private final class StackRailView: NSView {
    var onDrag: ((CGPoint) -> Void)?
    private var dragGesture = TabRailDragGesture()

    override func draw(_: NSRect) {
        let pill = bounds.insetBy(dx: 4, dy: 2)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.width / 2, yRadius: pill.width / 2)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        let dot: CGFloat = 2
        for offset in [-8.0, -2.0, 4.0] as [CGFloat] {
            NSBezierPath(ovalIn: CGRect(x: bounds.midX - dot / 2, y: bounds.midY + offset, width: dot, height: dot))
                .fill()
        }
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with _: NSEvent) {
        dragGesture.press(visualIndex: 0, at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with _: NSEvent) {
        let location = NSEvent.mouseLocation
        guard dragGesture.drag(to: location) != nil else { return }
        onDrag?(location)
    }

    override func mouseUp(with _: NSEvent) {
        dragGesture.release()
    }
}
