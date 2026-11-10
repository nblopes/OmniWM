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
        let layout = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width)
        XCTAssertTrue(layout.showsLabels)
        XCTAssertEqual(layout.documentLength, 800)
        XCTAssertEqual(layout.contentRects.map(\.height), lengths)
        XCTAssertEqual(layout.hitRects.map(\.height), [80 + overlap, 120 + overlap, 60])
        XCTAssertEqual(layout.tabRects.map(\.height), [80 + overlap, 120 + 2 * overlap, 60 + overlap])
        XCTAssertEqual(layout.tabRects.first?.minY, padding)
        for (content, hit) in zip(layout.contentRects, layout.hitRects) {
            XCTAssertEqual(content.minY, hit.minY)
        }
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

    func testContentLengthsFollowTheNameAndAreCapped() {
        let short = SidewaysTabMetrics.contentLength(labelWidth: 30)
        let long = SidewaysTabMetrics.contentLength(labelWidth: 120)
        XCTAssertEqual(short, SidewaysTabMetrics.iconOnlyLength + SidewaysTabMetrics.iconLabelGap + 30)
        XCTAssertGreaterThan(long, short)
        XCTAssertEqual(SidewaysTabMetrics.contentLength(labelWidth: 1000), SidewaysTabMetrics.maximumContentLength)
        let capped = SidewaysTabLayout(contentLengths: [1000, 1000], viewportLength: 800, width: width)
        XCTAssertEqual(capped.hitRects.first?.height, SidewaysTabMetrics.maximumTabLength)
        XCTAssertEqual(capped.contentRects.first?.height, SidewaysTabMetrics.maximumContentLength)
    }

    func testContentStaysPutWhicheverTabIsSelected() {
        let lengths: [CGFloat] = [80, 120, 60, 90]
        let plain = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width)
        for active in lengths.indices {
            let selected = SidewaysTabLayout(
                contentLengths: lengths, viewportLength: 800, width: width, activeVisualIndex: active
            )
            XCTAssertEqual(selected.contentRects, plain.contentRects)
            for (index, content) in selected.contentRects.enumerated() {
                for other in selected.tabRects.indices where other != index {
                    let cover = other == active || (other == index - 1 && index != active)
                    guard cover else { continue }
                    XCTAssertFalse(content.intersects(selected.tabRects[other].insetBy(dx: 0, dy: 0.5)))
                }
            }
        }
    }

    func testTabsDropTheirNamesWhenTheyDontFitAndScrollWhenIconsDont() {
        let lengths = Array(repeating: CGFloat(120), count: 5)
        let iconsOnly = SidewaysTabLayout(contentLengths: lengths, viewportLength: 400, width: width)
        XCTAssertFalse(iconsOnly.showsLabels)
        let icon = SidewaysTabMetrics.iconOnlyLength
        XCTAssertEqual(iconsOnly.hitRects.map(\.height), Array(repeating: icon + overlap, count: 4) + [icon])
        XCTAssertEqual(iconsOnly.contentRects.map(\.height), Array(repeating: icon, count: 5))
        XCTAssertEqual(iconsOnly.documentLength, 400)

        let scrolling = SidewaysTabLayout(
            contentLengths: Array(repeating: CGFloat(120), count: 20), viewportLength: 400, width: width
        )
        XCTAssertFalse(scrolling.showsLabels)
        XCTAssertEqual(scrolling.documentLength, 20 * icon + 19 * overlap + 2 * padding)
    }

    func testTheSelectedTabComesInFrontOfItsNeighbours() {
        let lengths: [CGFloat] = [80, 120, 60, 90]
        let plain = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width)
        let selected = SidewaysTabLayout(
            contentLengths: lengths, viewportLength: 800, width: width, activeVisualIndex: 2
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
        let layout = SidewaysTabLayout(contentLengths: [80, 120], viewportLength: 600, width: width)
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
        XCTAssertEqual(active.hitRect.height, SidewaysTabMetrics.iconOnlyLength + 2 * overlap)
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
        strip.document.updateLayer()
        XCTAssertFalse(strip.document.hasPendingLayerUpdate)

        strip.update(tabs: strip.tabs, activeVisualIndex: strip.activeVisualIndex)
        XCTAssertFalse(strip.document.hasPendingLayerUpdate)

        strip.update(tabs: strip.tabs, activeVisualIndex: 1)
        XCTAssertTrue(strip.document.hasPendingLayerUpdate)
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
        let placed = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width, firstTabTop: 300)
        XCTAssertEqual(placed.tabRects.first?.minY, 300)
        XCTAssertEqual(placed.documentLength, 800)

        let clamped = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width, firstTabTop: 2000)
        XCTAssertEqual(clamped.tabRects.first?.maxY, 800 - padding)

        let top = SidewaysTabLayout(contentLengths: lengths, viewportLength: 800, width: width, firstTabTop: 0)
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

    func testATitleChangeRedrawsNothing() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, _, strip) = try views(manager, info)
        strip.document.updateLayer()
        let retitled = strip.tabs.map { tab in
            var copy = TabRailTabInfo(
                visualIndex: tab.visualIndex, token: tab.token, windowId: tab.windowId, appName: tab.appName,
                title: (tab.title ?? "") + " (changed)", isActive: tab.isActive
            )
            copy.icon = tab.icon
            return copy
        }

        strip.update(tabs: retitled, activeVisualIndex: strip.activeVisualIndex)

        XCTAssertFalse(strip.document.hasPendingLayerUpdate)
        XCTAssertEqual(strip.tabs.map(\.title), retitled.map(\.title))
    }

    func testHoverSelectionAndTuckOnlySwapLayers() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 4, active: 1)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, _, strip) = try views(manager, info)
        let document = strip.document
        document.applyLayers()
        func contents() -> [ObjectIdentifier?] {
            (0 ..< 4).map { index in
                document.tabLayers(at: index)?.content.contents.map { ObjectIdentifier($0 as AnyObject) }
            }
        }
        func paths() -> [CGPath?] {
            (0 ..< 4).map { document.tabLayers(at: $0)?.shape.path }
        }
        let resting = contents()
        let restingPaths = paths()
        XCTAssertTrue(resting.allSatisfy { $0 != nil })

        strip.updateHover(3)
        document.applyLayers()
        XCTAssertEqual(Array(contents().prefix(3)), Array(resting.prefix(3)))
        XCTAssertEqual(paths(), restingPaths)

        strip.updateHover(nil)
        document.applyLayers()
        XCTAssertEqual(contents(), resting)

        strip.showsTuck = false
        document.applyLayers()
        XCTAssertEqual(contents(), resting)
        XCTAssertEqual(paths()[0], restingPaths[0])
        XCTAssertNotEqual(paths()[1], restingPaths[1])
        strip.showsTuck = true

        strip.update(tabs: strip.tabs, activeVisualIndex: 2)
        document.applyLayers()
        let selected = contents()
        XCTAssertEqual(selected[0], resting[0])
        XCTAssertEqual(selected[3], resting[3])
        XCTAssertEqual(
            (0 ..< 4).map { document.tabLayers(at: $0)?.content.frame },
            document.layout.contentRects.map(Optional.some)
        )

        strip.update(tabs: strip.tabs, activeVisualIndex: 1)
        document.applyLayers()
        XCTAssertEqual(contents(), resting)
    }

    func testNoLayerChangeAnimates() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        let info = makeInfo(count: 3)
        manager.updateRails([info], style: .sidewaysTabs)
        let (_, _, strip) = try views(manager, info)
        strip.document.applyLayers()

        strip.updateHover(2)
        strip.showsTuck = false
        strip.update(tabs: strip.tabs, activeVisualIndex: 2)
        strip.document.applyLayers()

        for index in 0 ..< 3 {
            let layers = try XCTUnwrap(strip.document.tabLayers(at: index))
            XCTAssertNil(layers.shape.animationKeys())
            XCTAssertNil(layers.content.animationKeys())
        }
    }

    func testLayersMatchTheDrawnStripPixelForPixel() throws {
        let manager = TabRailManager(motionPolicy: MotionPolicy(animationsEnabled: false))
        defer { manager.removeAll() }
        var worst: (fraction: Double, mean: Double, label: String) = (0, 0, "")
        for count in [1, 3, 5] {
            for active in Set([0, count / 2, count - 1]).sorted() {
                for hovered in [nil, (active + 1) % count] as [Int?] {
                    for tucked in [true, false] {
                        for dark in [false, true] {
                            let info = makeInfo(count: count, active: active, names: (0 ..< count).map {
                                ["Safari", "Mail", "A much longer name", "Warp", "Ghostty"][$0 % 5]
                            })
                            manager.updateRails([info], style: .sidewaysTabs)
                            let (_, _, strip) = try views(manager, info)
                            let document = strip.document
                            document.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                            strip.updateHover(hovered == active ? nil : hovered)
                            strip.showsTuck = tucked
                            document.applyLayers()
                            let size = document.bounds.size
                            let layers = try image(size: size) { context in
                                if document.layer?.contentsAreFlipped() == true {
                                    context.translateBy(x: 0, y: size.height)
                                    context.scaleBy(x: 1, y: -1)
                                }
                                document.layer?.render(in: context)
                            }
                            let reference = try image(size: size) { context in
                                context.translateBy(x: 0, y: size.height)
                                context.scaleBy(x: 1, y: -1)
                                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                                drawReference(document, dark: dark, in: context)
                            }
                            let difference = Self.difference(layers, reference)
                            if difference.fraction >= worst.fraction {
                                worst = (
                                    difference.fraction,
                                    difference.mean,
                                    "count=\(count) active=\(active) hovered=\(String(describing: hovered))"
                                        + " tucked=\(tucked) dark=\(dark)"
                                )
                            }
                            manager.removeAll()
                        }
                    }
                }
            }
        }
        XCTAssertLessThan(worst.fraction, 0.01, "worst \(worst.label): mean \(worst.mean)")
        XCTAssertLessThan(worst.mean, 3, "worst \(worst.label): fraction \(worst.fraction)")
    }

    private func image(size: CGSize, draw: (CGContext) -> Void) throws -> NSBitmapImageRep {
        let scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
        ))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func difference(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep
    ) -> (fraction: Double, mean: Double) {
        guard let left = lhs.bitmapData, let right = rhs.bitmapData, lhs.bytesPerRow == rhs.bytesPerRow,
              lhs.pixelsHigh == rhs.pixelsHigh
        else { return (1, 255) }
        let count = lhs.bytesPerRow * lhs.pixelsHigh
        var total = 0
        var differing = 0
        for pixel in stride(from: 0, to: count, by: 4) {
            var largest = 0
            for channel in 0 ..< 4 {
                let delta = abs(Int(left[pixel + channel]) - Int(right[pixel + channel]))
                total += delta
                largest = max(largest, delta)
            }
            if largest > 64 { differing += 1 }
        }
        return (Double(differing) / Double(count / 4), Double(total) / Double(count))
    }

    private func drawReference(_ document: TabRailSidewaysTabsDocumentView, dark: Bool, in context: CGContext) {
        let layout = document.layout
        let tabs = document.tabs
        let active = layout.tabRects.indices.contains(document.activeVisualIndex) ? document.activeVisualIndex : nil
        func shades(_ index: Int, _ isActive: Bool) -> TabRailTabColor.Shades {
            TabRailTabColor.shades(
                base: TabRailTabColor.baseColor(for: tabs[index].icon, app: tabs[index].token?.pid),
                hovered: !isActive && index == document.hoveredVisualIndex,
                dark: dark
            )
        }
        func fill(_ shape: CGPath, _ color: NSColor, alpha: CGFloat, blur: CGFloat) {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -2), blur: blur,
                color: NSColor.black.withAlphaComponent(alpha).cgColor
            )
            context.addPath(shape)
            context.setFillColor(color.cgColor)
            context.fillPath()
            context.restoreGState()
        }
        func content(_ index: Int, _ isActive: Bool, _ label: NSColor) {
            SidewaysTabContent.draw(
                label: layout.showsLabels ? TabRailSidewaysTabsDocumentView.label(for: tabs[index]) : nil,
                icon: tabs[index].icon, in: layout.contentRects[index], active: isActive, labelColor: label
            )
        }
        for index in layout.tabRects.indices.reversed() where index != active {
            let colors = shades(index, false)
            fill(TabRailSidewaysTabsDocumentView.tabPath(in: layout.tabRects[index]), colors.fill, alpha: 0.3, blur: 4)
            content(index, false, colors.label)
        }
        guard let active else { return }
        let colors = shades(active, true)
        let shape = CGMutablePath()
        shape.addPath(TabRailSidewaysTabsDocumentView.tabPath(in: layout.tabRects[active]))
        let bandRadius = SidewaysTabMetrics.bandWidth / 2
        let bounds = document.bounds
        shape.addRoundedRect(
            in: layout.bandRect(
                reaching: document.showsTuck ? bounds.maxX : min(bounds.maxX, SidewaysTabMetrics.stripWidth)
            ),
            cornerWidth: bandRadius, cornerHeight: bandRadius
        )
        fill(shape, colors.fill, alpha: 0.4, blur: 6)
        content(active, true, colors.label)
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
