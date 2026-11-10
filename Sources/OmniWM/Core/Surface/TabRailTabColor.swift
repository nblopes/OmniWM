// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
enum TabRailTabColor {
    private final class Entry {
        let color: NSColor?

        init(_ color: NSColor?) {
            self.color = color
        }
    }

    private static let cache = NSCache<NSImage, Entry>()
    private static let sampleSide = 16
    private static let hueBins = 12
    private static let minimumSaturation: CGFloat = 0.25
    private static let minimumBrightness: CGFloat = 0.2
    private static let minimumWeightedPixels: CGFloat = 6

    private static var colorsByApp: [pid_t: Entry] = [:]
    private static var terminationObserver: NSObjectProtocol?

    struct Shades {
        let fill: NSColor
        let label: NSColor
    }

    private struct ShadeKey: Hashable {
        let red: CGFloat?
        let green: CGFloat?
        let blue: CGFloat?
        let hovered: Bool
        let dark: Bool
    }

    private static var shadesByKey: [ShadeKey: Shades] = [:]
    private static let shadeCacheLimit = 256

    static var cachedAppCount: Int {
        colorsByApp.count
    }

    static func baseColor(for icon: NSImage?, app pid: pid_t? = nil) -> NSColor? {
        if let pid, let entry = colorsByApp[pid] { return entry.color }
        guard let icon else { return nil }
        let entry = cache.object(forKey: icon) ?? Entry(dominantColor(of: icon))
        cache.setObject(entry, forKey: icon)
        if let pid {
            observeTerminations()
            colorsByApp[pid] = entry
        }
        return entry.color
    }

    static func forgetApp(_ pid: pid_t) {
        colorsByApp[pid] = nil
    }

    private static func observeTerminations() {
        guard terminationObserver == nil else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            Task { @MainActor in forgetApp(pid) }
        }
    }

    static func shades(base: NSColor?, hovered: Bool, dark: Bool) -> Shades {
        let rgb = base?.usingColorSpace(.sRGB)
        let key = ShadeKey(
            red: rgb?.redComponent, green: rgb?.greenComponent, blue: rgb?.blueComponent,
            hovered: hovered, dark: dark
        )
        if let shades = shadesByKey[key] { return shades }
        if shadesByKey.count >= shadeCacheLimit { shadesByKey.removeAll(keepingCapacity: true) }
        let fill = fill(base: base, hovered: hovered, dark: dark)
        let shades = Shades(fill: fill, label: label(on: fill))
        shadesByKey[key] = shades
        return shades
    }

    static func dominantColor(of image: NSImage) -> NSColor? {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                      bytesPerRow: side * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var weights = [CGFloat](repeating: 0, count: hueBins)
        var sums = [(red: CGFloat, green: CGFloat, blue: CGFloat)](repeating: (0, 0, 0), count: hueBins)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let red = CGFloat(pixels[offset]) / 255 / alpha
            let green = CGFloat(pixels[offset + 1]) / 255 / alpha
            let blue = CGFloat(pixels[offset + 2]) / 255 / alpha
            let color = NSColor(srgbRed: min(1, red), green: min(1, green), blue: min(1, blue), alpha: 1)
            let saturation = color.saturationComponent
            let brightness = color.brightnessComponent
            guard saturation >= minimumSaturation, brightness >= minimumBrightness else { continue }
            let bin = min(hueBins - 1, Int(color.hueComponent * CGFloat(hueBins)))
            let weight = saturation * brightness
            weights[bin] += weight
            sums[bin].red += red * weight
            sums[bin].green += green * weight
            sums[bin].blue += blue * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[best] >= minimumWeightedPixels * minimumSaturation * minimumBrightness
        else { return nil }
        let total = weights[best]
        return NSColor(
            srgbRed: min(1, sums[best].red / total),
            green: min(1, sums[best].green / total),
            blue: min(1, sums[best].blue / total),
            alpha: 1
        )
    }

    static func fill(base: NSColor?, hovered: Bool, dark: Bool) -> NSColor {
        let lift: CGFloat = hovered ? (dark ? 0.06 : -0.04) : 0
        guard let base = base?.usingColorSpace(.sRGB) else {
            return NSColor(white: (dark ? 0.36 : 0.80) + lift, alpha: 1)
        }
        let saturation = dark ? min(base.saturationComponent, 0.75) : min(base.saturationComponent, 0.65)
        let brightness: CGFloat = dark ? 0.55 : 0.78
        return readable(
            hue: base.hueComponent, saturation: saturation, brightness: min(1, brightness + lift), towardsDark: dark
        )
    }

    static func label(on fill: NSColor) -> NSColor {
        prefersDarkLabel(on: fill) ? NSColor(white: 0, alpha: 0.95) : NSColor(white: 1, alpha: 0.95)
    }

    private static let minimumLabelContrast: CGFloat = 4.8

    private static func readable(
        hue: CGFloat, saturation: CGFloat, brightness: CGFloat, towardsDark: Bool
    ) -> NSColor {
        var value = brightness
        var color = NSColor(hue: hue, saturation: saturation, brightness: value, alpha: 1)
        while bestLabelContrast(on: color) < minimumLabelContrast, value > 0.02, value < 0.98 {
            value += towardsDark ? -0.02 : 0.02
            color = NSColor(
                hue: hue,
                saturation: towardsDark ? saturation : saturation * 0.97,
                brightness: value,
                alpha: 1
            )
        }
        return color
    }

    private static func prefersDarkLabel(on fill: NSColor) -> Bool {
        let luminance = relativeLuminance(of: fill)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    private static func bestLabelContrast(on fill: NSColor) -> CGFloat {
        let luminance = relativeLuminance(of: fill)
        return max((luminance + 0.05) / 0.05, 1.05 / (luminance + 0.05))
    }

    static func relativeLuminance(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }
}
