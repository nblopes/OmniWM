// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class TabRailSidewaysTabsTests: XCTestCase {
    private let width = SidewaysTabMetrics.stripWidth
    private let padding = SidewaysTabMetrics.stripEndPadding
    private let overlap = SidewaysTabMetrics.overlap
    private let inset = SidewaysTabMetrics.leadingInset

    func testEachTabIsAsLongAsItsContentAndTheyStackFromTheTop() {
        let lengths: [CGFloat] = [80, 120, 60]
        let layout = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 800, width: width)
        XCTAssertTrue(layout.showsLabels)
        XCTAssertEqual(layout.documentLength, 800)
        XCTAssertEqual(layout.hitRects.map(\.height), lengths)
        XCTAssertEqual(layout.tabRects.map(\.height), [80, 120 + overlap, 60 + overlap])
        XCTAssertEqual(layout.tabRects.first?.minY, padding)
        for (previous, next) in zip(layout.hitRects, layout.hitRects.dropFirst()) {
            XCTAssertEqual(previous.maxY, next.minY)
        }
        for (upper, lower) in zip(layout.tabRects, layout.tabRects.dropFirst()) {
            XCTAssertEqual(upper.maxY - lower.minY, overlap)
        }
        for rect in layout.tabRects {
            XCTAssertEqual(rect.minX, inset)
            XCTAssertEqual(rect.width, width - inset - SidewaysTabMetrics.bandWidth)
        }
    }

    func testLabelledLengthsFollowTheNameAndAreCapped() {
        let short = SidewaysTabMetrics.labelledLength(labelWidth: 30)
        let long = SidewaysTabMetrics.labelledLength(labelWidth: 120)
        XCTAssertEqual(
            short,
            SidewaysTabMetrics.iconOnlyLength + SidewaysTabMetrics.iconLabelGap + 30 + SidewaysTabMetrics.overlap
        )
        XCTAssertGreaterThan(long, short)
        XCTAssertEqual(
            SidewaysTabMetrics.labelledLength(labelWidth: 1000),
            SidewaysTabMetrics.maximumTabLength
        )
        let capped = SidewaysTabLayout(labelledLengths: [1000], viewportLength: 800, width: width)
        XCTAssertEqual(capped.hitRects.first?.height, SidewaysTabMetrics.maximumTabLength)
    }

    func testTabsDropTheirNamesWhenTheyDontFitAndScrollWhenIconsDont() {
        let lengths = Array(repeating: CGFloat(120), count: 5)
        let iconsOnly = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 400, width: width)
        XCTAssertFalse(iconsOnly.showsLabels)
        XCTAssertEqual(
            iconsOnly.hitRects.map(\.height),
            Array(repeating: SidewaysTabMetrics.iconOnlyLength, count: 5)
        )
        XCTAssertEqual(iconsOnly.documentLength, 400)

        let scrolling = SidewaysTabLayout(
            labelledLengths: Array(repeating: CGFloat(120), count: 20), viewportLength: 400, width: width
        )
        XCTAssertFalse(scrolling.showsLabels)
        XCTAssertEqual(scrolling.documentLength, 20 * SidewaysTabMetrics.iconOnlyLength + 2 * padding)
    }

    func testTheSelectedTabComesInFrontOfItsNeighbours() {
        let lengths: [CGFloat] = [80, 120, 60, 90]
        let plain = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 800, width: width)
        let selected = SidewaysTabLayout(
            labelledLengths: lengths, viewportLength: 800, width: width, activeVisualIndex: 2
        )
        XCTAssertEqual(selected.tabRects, plain.tabRects)
        XCTAssertEqual(selected.hitRects[2], selected.tabRects[2])
        XCTAssertEqual(selected.hitRects[1].maxY, selected.tabRects[2].minY)
        XCTAssertEqual(selected.hitRects[1].height, plain.hitRects[1].height - overlap)
        XCTAssertEqual(selected.hitRects[3], plain.hitRects[3])
        XCTAssertEqual(selected.hitRects[0], plain.hitRects[0])
        for (upper, lower) in zip(selected.hitRects, selected.hitRects.dropFirst()) {
            XCTAssertEqual(upper.maxY, lower.minY)
        }
    }

    func testTheBandRunsTheStripsFullLengthAndReachesUnderTheWindowOnlyWhenTucked() {
        let layout = SidewaysTabLayout(labelledLengths: [80, 120], viewportLength: 600, width: width)
        let band = SidewaysTabMetrics.bandWidth
        let tuck = SidewaysTabMetrics.tuckUnderWindow
        XCTAssertEqual(layout.bandRect(reaching: width), CGRect(x: width - band, y: 0, width: band, height: 600))
        XCTAssertEqual(
            layout.bandRect(reaching: width + tuck),
            CGRect(x: width - band, y: 0, width: band + tuck, height: 600)
        )
        XCTAssertEqual(layout.tabRects.first?.maxX, layout.bandRect(reaching: width).minX)
    }

    func testTheStripAlwaysReachesUnderItsWindow() {
        XCTAssertEqual(TabRailStyle.sidewaysTabs.windowOverlap, SidewaysTabMetrics.tuckUnderWindow)
        XCTAssertEqual(TabRailStyle.compact.windowOverlap, 0)
        let tile = CGRect(x: 300, y: 300, width: 400, height: 800)
        let frame = TabRailPlacement.frame(for: tile, tabCount: 3, style: .sidewaysTabs)
        XCTAssertEqual(frame.minX, tile.minX)
        XCTAssertEqual(frame.maxX, tile.minX + width + SidewaysTabMetrics.tuckUnderWindow)
    }

    func testTheStripRunsTheColumnsHeightClearOfItsCorners() {
        let allowance = SidewaysTabMetrics.windowCornerAllowance
        XCTAssertEqual(SidewaysTabLayout.fittedHeight(tabCount: 2, availableHeight: 900), 900 - 2 * allowance)
        XCTAssertEqual(SidewaysTabLayout.fittedHeight(tabCount: 2, availableHeight: 2 * allowance + 40), 0)
        XCTAssertEqual(SidewaysTabLayout.fittedHeight(tabCount: 0, availableHeight: 900), 0)
    }

    func testClickHoverAndAccessibilityAgreeIncludingOverlappedParts() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        var selected: Int?
        manager.onSelect = { _, index, _ in selected = index }
        for count in [2, 5, 12] {
            for active in [0, count / 2, count - 1] {
                let info = makeInfo(count: count, active: active)
                manager.updateRails([info], style: .sidewaysTabs)
                let (window, view, strip) = try views(manager, info)
                XCTAssertEqual(window.frame.width, width + SidewaysTabMetrics.tuckUnderWindow)
                XCTAssertEqual(window.frame.minX, info.tileFrame.minX)
                let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
                let items = strip.railLayout(in: view).items.filter { !$0.hitRect.isEmpty }
                for item in items {
                    let center = CGPoint(x: item.hitRect.midX, y: item.hitRect.midY)
                    XCTAssertEqual(view.item(at: center)?.visualIndex, item.visualIndex)
                    selected = nil
                    let hitView = try XCTUnwrap(view.hitTest(center))
                    hitView.mouseDown(with: try event(.leftMouseDown, at: center, in: window))
                    XCTAssertEqual(selected, item.visualIndex)
                    view.mouseMoved(with: try event(.mouseMoved, at: center, in: window))
                    XCTAssertTrue(window.hoverCard.isVisible)
                    XCTAssertEqual(strip.document.hoveredVisualIndex, item.visualIndex)
                    XCTAssertEqual(
                        children[item.visualIndex].accessibilityFrame(),
                        window.convertToScreen(item.hitRect)
                    )
                }
                for (upper, lower) in zip(items, items.dropFirst()) {
                    XCTAssertFalse(lower.hitRect.intersects(upper.hitRect))
                }
            }
        }
    }

    func testTheOverlappedPartOfATabBelongsToTheTabAbove() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 2)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, view, strip) = try views(manager, info)
        let document = strip.document
        let lowerShape = document.convert(document.layout.tabRects[1], to: view)
        let upperHit = document.convert(document.layout.hitRects[0], to: view)
        XCTAssertGreaterThan(lowerShape.intersection(upperHit).height, 0)
        let underUpper = CGPoint(x: upperHit.midX, y: lowerShape.intersection(upperHit).midY)
        XCTAssertEqual(view.item(at: underUpper)?.visualIndex, 0)

        manager.updateRails([makeInfo(count: 2, active: 1, key: info.key)], style: .sidewaysTabs)
        XCTAssertEqual(view.item(at: underUpper)?.visualIndex, 1)
    }

    func testTheActiveTabIsRevealedWhenTheStripScrolls() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 20, active: 18, height: 400)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, view, strip) = try views(manager, info)
        let viewport = strip.convert(strip.bounds, to: view)
        let active = try XCTUnwrap(strip.railLayout(in: view).items.first { $0.visualIndex == 18 })
        XCTAssertGreaterThan(strip.scrollView.contentView.bounds.minY, 0)
        XCTAssertTrue(viewport.contains(active.hitRect))
        XCTAssertEqual(active.hitRect.height, SidewaysTabMetrics.iconOnlyLength + overlap)
    }

    func testLongerNamesMakeLongerTabs() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 2, names: ["Go", "A much longer app"])
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, _, strip) = try views(manager, info)
        let lengths = strip.document.layout.hitRects.map(\.height)
        XCTAssertEqual(lengths.count, 2)
        XCTAssertLessThan(lengths[0], lengths[1])
    }

    func testLabelsUseTheAppNameWithFallbacks() {
        func tab(appName: String?, title: String?) -> TabRailTabInfo {
            TabRailTabInfo(visualIndex: 2, token: nil, windowId: nil, appName: appName, title: title, isActive: false)
        }
        XCTAssertEqual(TabRailSidewaysTabsDocumentView.label(for: tab(appName: "Safari", title: "Page")), "Safari")
        XCTAssertEqual(TabRailSidewaysTabsDocumentView.label(for: tab(appName: "", title: "Page")), "Page")
        XCTAssertEqual(TabRailSidewaysTabsDocumentView.label(for: tab(appName: nil, title: nil)), "Window 3")
    }

    func testSwitchingStyleReplacesTheStrip() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, view, _) = try views(manager, info)
        manager.updateRails([info], style: .appIcons)
        XCTAssertFalse(view.subviews.contains { $0 is TabRailSidewaysTabsView })
        XCTAssertTrue(view.subviews.contains { $0 is TabRailIconView })
        manager.updateRails([info], style: .sidewaysTabs)
        XCTAssertFalse(view.subviews.contains { $0 is TabRailIconView })
        XCTAssertEqual(view.subviews.filter { $0 is TabRailSidewaysTabsView }.count, 1)
    }

    func testARestackReplayKeepsWhereTheStripWasLastPlaced() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (window, _, _) = try views(manager, info)
        let moved = info.tileFrame.offsetBy(dx: -150, dy: 20)
        manager.applyAnimationGeometry([
            TabRailGeometryCommand(key: info.key, tileFrame: moved, visibleTileFrame: moved)
        ])
        let placed = window.appliedFrame
        XCTAssertEqual(placed.minX, moved.minX)

        manager.updateRails([info], forceOrdering: true, style: .sidewaysTabs)
        XCTAssertEqual(window.appliedFrame, placed)

        let next = makeInfo(count: 3, height: 700, key: info.key)
        manager.updateRails([next], style: .sidewaysTabs)
        XCTAssertEqual(window.appliedFrame.minX, next.tileFrame.minX)
    }

    func testAnUnchangedUpdateDoesNotRedrawTheStrip() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, _, strip) = try views(manager, info)
        strip.document.displayIfNeeded()
        XCTAssertFalse(strip.document.needsDisplay)

        strip.update(tabs: strip.tabs, activeVisualIndex: strip.activeVisualIndex)
        XCTAssertFalse(strip.document.needsDisplay)

        strip.update(tabs: strip.tabs, activeVisualIndex: 1)
        XCTAssertTrue(strip.document.needsDisplay)
    }

    func testClickingTheStripDoesNotLiftItAboveItsWindow() {
        let view = TabRailView(frame: CGRect(x: 0, y: 0, width: 50, height: 600), motionPolicy: MotionPolicy())
        let click = NSEvent()
        view.update(tabs: makeInfo(count: 2).tabs, activeVisualIndex: 0, style: .compact)
        XCTAssertFalse(view.shouldDelayWindowOrdering(for: click))
        view.update(tabs: makeInfo(count: 2).tabs, activeVisualIndex: 0, style: .sidewaysTabs)
        XCTAssertTrue(view.shouldDelayWindowOrdering(for: click))
    }

    func testTheTuckTakesNoClicks() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (window, _, _) = try views(manager, info)
        let hit = try XCTUnwrap(window.hitFrame)

        XCTAssertEqual(hit.minX, window.appliedFrame.minX)
        XCTAssertEqual(hit.width, TabRailStyle.sidewaysTabs.hitWidth)
        XCTAssertLessThanOrEqual(hit.maxX, info.tileFrame.minX + TabRailStyle.sidewaysTabs.reservedWidth)
    }

    func testThePointerOverTheStripHidesTheTuck() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (window, view, strip) = try views(manager, info)
        let middle = view.bounds.midY
        XCTAssertTrue(strip.showsTuck)

        view.mouseMoved(with: try event(.mouseMoved, at: CGPoint(x: 20, y: middle), in: window))
        XCTAssertFalse(strip.showsTuck)

        let overTuck = CGPoint(x: view.bounds.width - SidewaysTabMetrics.tuckUnderWindow / 2, y: middle)
        view.mouseMoved(with: try event(.mouseMoved, at: overTuck, in: window))
        XCTAssertTrue(strip.showsTuck)

        view.mouseMoved(with: try event(.mouseMoved, at: CGPoint(x: 20, y: middle), in: window))
        view.mouseExited(with: try event(.mouseMoved, at: CGPoint(x: -20, y: middle), in: window))
        XCTAssertTrue(strip.showsTuck)
    }

    func testATravellingTabKeepsItsHeightAndClampsInsideTheStrip() {
        let lengths: [CGFloat] = [120]
        let placed = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 800, width: width, firstTabTop: 300)
        XCTAssertEqual(placed.tabRects.first?.minY, 300)
        XCTAssertEqual(placed.documentLength, 800)

        let clamped = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 800, width: width, firstTabTop: 2000)
        XCTAssertEqual(clamped.tabRects.first?.maxY, 800 - padding)

        let top = SidewaysTabLayout(labelledLengths: lengths, viewportLength: 800, width: width, firstTabTop: 0)
        XCTAssertEqual(top.tabRects.first?.minY, padding)
    }

    func testATravellingTabAlwaysDrawsItsTuck() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let base = makeInfo(count: 1)
        let info = TabRailInfo(
            workspaceId: base.workspaceId, owner: base.owner, plannedSeq: 1, tileFrame: base.tileFrame,
            tabCount: 1, activeVisualIndex: 0, activeWindowId: nil, tabs: base.tabs, travellingTabTop: 240
        )
        manager.updateRails([info], style: .sidewaysTabs)
        let (window, view, strip) = try views(manager, info)

        view.mouseMoved(with: try event(.mouseMoved, at: CGPoint(x: 20, y: view.bounds.midY), in: window))

        XCTAssertTrue(strip.showsTuck)
        XCTAssertEqual(strip.firstTabTop, 240)
        XCTAssertEqual(strip.tabTop(0), 240)
    }

    func testAPulledTabRemembersItsHeightInTheStrip() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, view, strip) = try views(manager, info)
        let token = try XCTUnwrap(info.tabs[2].token)

        let top = try XCTUnwrap(view.tabTop(2))
        XCTAssertEqual(top, try XCTUnwrap(strip.tabTop(2)))
        XCTAssertGreaterThan(top, try XCTUnwrap(view.tabTop(1)))
        manager.notePulledTab(token, top: top)

        XCTAssertEqual(manager.pulledTabTop(for: token), top)
        XCTAssertNil(manager.pulledTabTop(for: try XCTUnwrap(info.tabs[1].token)))
    }

    private func makeInfo(
        count: Int, active: Int = 0, height: CGFloat = 800, names: [String]? = nil, key: TabRailKey? = nil
    ) -> TabRailInfo {
        TabRailInfo(
            workspaceId: key?.workspaceId ?? UUID(), owner: key?.owner ?? .niriColumn(NodeId()), plannedSeq: 1,
            tileFrame: CGRect(x: 300, y: 300, width: 400, height: height),
            tabCount: count, activeVisualIndex: active, activeWindowId: nil,
            tabs: (0 ..< count).map { index in
                TabRailTabInfo(
                    visualIndex: index, token: WindowToken(pid: getpid(), windowId: index), windowId: nil,
                    appName: names?[index] ?? "App \(index)", title: "Window \(index)", isActive: index == active
                )
            }
        )
    }

    private func views(
        _ manager: TabRailManager,
        _ info: TabRailInfo
    ) throws -> (TabRailWindow, TabRailView, TabRailSidewaysTabsView) {
        let window = try XCTUnwrap(manager.existingWindow(for: info.key) as? TabRailWindow)
        let view = try XCTUnwrap(window.contentView as? TabRailView)
        let strip = try XCTUnwrap(view.subviews.first { $0 is TabRailSidewaysTabsView } as? TabRailSidewaysTabsView)
        return (window, view, strip)
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0
        ))
    }
}
