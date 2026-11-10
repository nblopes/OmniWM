// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class TabRailTabColorTests: XCTestCase {
    func testAColouredIconGivesItsColour() throws {
        let icon = image { rect in
            NSColor(srgbRed: 0.9, green: 0.95, blue: 0.95, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.1, green: 0.7, blue: 0.5, alpha: 1).setFill()
            rect.insetBy(dx: rect.width / 5, dy: rect.height / 5).fill()
        }
        let color = try XCTUnwrap(TabRailTabColor.dominantColor(of: icon)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.hueComponent, 157.0 / 360.0, accuracy: 0.04)
        XCTAssertGreaterThan(color.saturationComponent, 0.6)
    }

    func testTheStrongestHueWinsOverAPaleBackground() throws {
        let icon = image { rect in
            NSColor(srgbRed: 0.7, green: 0.75, blue: 0.95, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.95, green: 0.3, blue: 0.1, alpha: 1).setFill()
            rect.insetBy(dx: rect.width / 4, dy: rect.height / 4).fill()
        }
        let color = try XCTUnwrap(TabRailTabColor.dominantColor(of: icon)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(color.hueComponent, 0.08)
    }

    func testGreyOrMonochromeIconsGiveTheNeutralColour() {
        let grey = image { rect in
            NSColor(white: 0.5, alpha: 1).setFill()
            rect.fill()
            NSColor.black.setFill()
            rect.insetBy(dx: 4, dy: 4).fill()
        }
        XCTAssertNil(TabRailTabColor.dominantColor(of: grey))
        XCTAssertNil(TabRailTabColor.dominantColor(of: image { _ in }))
        XCTAssertNil(TabRailTabColor.baseColor(for: nil))
    }

    func testAnAppsColourIsWorkedOutOnceAndKeptAcrossNewIconImages() {
        let pid: pid_t = 987_654
        let blue = image { rect in
            NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1).setFill()
            rect.fill()
        }
        let red = image { rect in
            NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
            rect.fill()
        }
        let first = TabRailTabColor.baseColor(for: blue, app: pid)
        XCTAssertNotNil(first)
        XCTAssertEqual(TabRailTabColor.baseColor(for: red, app: pid), first)
        XCTAssertEqual(TabRailTabColor.baseColor(for: nil, app: pid), first)
    }

    func testAnAppThatQuitsIsForgotten() {
        let pid: pid_t = 938_406
        let icon = image { rect in
            NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1).setFill()
            rect.fill()
        }
        _ = TabRailTabColor.baseColor(for: icon, app: pid)
        let count = TabRailTabColor.cachedAppCount

        TabRailTabColor.forgetApp(pid)

        XCTAssertEqual(TabRailTabColor.cachedAppCount, count - 1)
    }

    func testShadesAreTheSameColoursAsTheFill() {
        let base = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.4, alpha: 1)
        for dark in [false, true] {
            for hovered in [false, true] {
                let shades = TabRailTabColor.shades(base: base, hovered: hovered, dark: dark)
                XCTAssertEqual(shades.fill, TabRailTabColor.fill(base: base, hovered: hovered, dark: dark))
                XCTAssertEqual(shades.label, TabRailTabColor.label(on: shades.fill))
            }
        }
    }

    func testLabelsStayReadableOnEveryShade() {
        let bases: [NSColor?] = [
            nil,
            NSColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 1),
            NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1),
            NSColor(srgbRed: 0.2, green: 0.8, blue: 0.3, alpha: 1),
            NSColor(srgbRed: 0.9, green: 0.1, blue: 0.2, alpha: 1)
        ]
        for base in bases {
            for dark in [false, true] {
                for hovered in [false, true] {
                    let fill = TabRailTabColor.fill(base: base, hovered: hovered, dark: dark)
                    let label = TabRailTabColor.label(on: fill)
                    XCTAssertGreaterThanOrEqual(contrast(fill, label), 4.5, "\(String(describing: base)) \(dark)")
                }
            }
        }
    }

    func testTheShadeKeepsTheIconsHueAndMostOfItsSaturation() throws {
        let warp = NSColor(srgbRed: 13 / 255, green: 137 / 255, blue: 172 / 255, alpha: 1)
        for dark in [false, true] {
            let fill = try XCTUnwrap(TabRailTabColor.fill(base: warp, hovered: false, dark: dark)
                .usingColorSpace(.sRGB))
            XCTAssertEqual(fill.hueComponent, warp.hueComponent, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(fill.saturationComponent, 0.6)
            XCTAssertGreaterThanOrEqual(fill.brightnessComponent, 0.4)
        }
    }

    private func contrast(_ fill: NSColor, _ label: NSColor) -> CGFloat {
        let labelRGB = label.usingColorSpace(.sRGB) ?? label
        let fillRGB = fill.usingColorSpace(.sRGB) ?? fill
        let alpha = labelRGB.alphaComponent
        let blended = NSColor(
            srgbRed: labelRGB.redComponent * alpha + fillRGB.redComponent * (1 - alpha),
            green: labelRGB.greenComponent * alpha + fillRGB.greenComponent * (1 - alpha),
            blue: labelRGB.blueComponent * alpha + fillRGB.blueComponent * (1 - alpha),
            alpha: 1
        )
        let first = TabRailTabColor.relativeLuminance(of: fill)
        let second = TabRailTabColor.relativeLuminance(of: blended)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func image(_ draw: (NSRect) -> Void) -> NSImage {
        let rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let image = NSImage(size: rect.size)
        guard let rep else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(rect)
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }
}
