import SwiftUI
import AppKit

/// Brand spectrum: midnight / navy / gold / white, plus system red for destructive only.
/// https://coolors.co/palette/000814-001d3d-003566-ffc300-ffd60a
///
/// Semantic roles adapt to Light / Dark. Prefer these over raw hex at call sites.
enum AppPalette {
    static let midnightHex = "#000814"
    static let navyDeepHex = "#001D3D"
    static let navyHex = "#003566"
    static let goldHex = "#FFC300"
    static let goldBrightHex = "#FFD60A"
    static let whiteHex = "#FFFFFF"

    static let brandHex = goldHex

    static let midnight = color(midnightHex)
    static let navyDeep = color(navyDeepHex)
    static let navy = color(navyHex)
    static let gold = color(goldHex)
    static let goldBright = color(goldBrightHex)
    static let white = color(whiteHex)

    static var brand: Color { gold }
    static var brandDeep: Color { goldBright }
    static var canvas: Color { Color.adaptive(lightHex: whiteHex, darkHex: midnightHex) }
    /// Light frosts white (widget canvas). Dark tints midnight. Never navy-wash Light.
    static var glassTint: Color { Color.adaptive(lightHex: whiteHex, darkHex: midnightHex) }
    static var onAccent: Color { midnight }
    static var onDanger: Color { white }
    static var controlOn: Color { Color.adaptive(lightHex: goldHex, darkHex: goldBrightHex) }

    static var link: Color { Color.adaptive(lightHex: navyHex, darkHex: goldHex) }
    static var code: Color { Color.adaptive(lightHex: navyDeepHex, darkHex: goldBrightHex) }
    static var text: Color { Color.adaptive(lightHex: midnightHex, darkHex: whiteHex) }
    static var image: Color { Color.adaptive(lightHex: goldHex, darkHex: goldBrightHex) }
    static var file: Color { Color.adaptive(lightHex: navyDeepHex, darkHex: whiteHex, darkAlpha: 0.78) }
    static var danger: Color { Color.red }
    static var memory: Color { gold }
    static var slate: Color { Color.adaptive(lightHex: midnightHex, darkHex: whiteHex) }

    static var stroke: Color { Color.adaptive(lightHex: navyHex, lightAlpha: 0.16, darkHex: goldHex, darkAlpha: 0.28) }
    static var chipFill: Color { Color.adaptive(lightHex: navyHex, lightAlpha: 0.08, darkHex: goldHex, darkAlpha: 0.14) }
    static var surface: Color { Color.adaptive(lightHex: whiteHex, lightAlpha: 0.82, darkHex: navyDeepHex, darkAlpha: 0.42) }
    static var surfaceSelected: Color { gold.opacity(0.20) }
    static var keycapFill: Color { Color.adaptive(lightHex: navyHex, lightAlpha: 0.06, darkHex: whiteHex, darkAlpha: 0.08) }
    static var highlight: Color { Color.adaptive(lightHex: navyHex, lightAlpha: 0.06, darkHex: whiteHex, darkAlpha: 0.28) }
    static var switchOff: Color { Color.adaptive(lightHex: navyHex, lightAlpha: 0.18, darkHex: navyDeepHex, darkAlpha: 1) }

    static func color(_ hex: String) -> Color {
        Color(hex: hex) ?? Color(red: 1, green: 0.84, blue: 0.04)
    }

    // Liquid Glass types exist only in the macOS 26 SDK (Swift 6.2+ toolchains).
    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    static func applyWindowGlass(
        _ glass: NSGlassEffectView,
        tintAmount: Double,
        appearance: NSAppearance? = nil
    ) {
        let amount = min(max(tintAmount, 0), 1)
        glass.style = amount < 0.33 ? .clear : .regular
        guard amount > 0.02 else {
            glass.tintColor = nil
            return
        }
        let resolved = appearance ?? glass.effectiveAppearance
        let dark = resolved.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            glass.tintColor = NSColor(hex: midnightHex)?.withAlphaComponent(0.08 + amount * 0.48)
        } else {
            glass.tintColor = NSColor(hex: whiteHex)?.withAlphaComponent(0.42 + amount * 0.50)
        }
    }

    @available(macOS 26.0, *)
    static func glass(
        tintAmount: Double,
        interactive: Bool,
        clearBias: Bool = false,
        scheme: ColorScheme
    ) -> Glass {
        let amount = min(max(tintAmount, 0), 1)
        var material: Glass = (clearBias || amount < 0.33) ? .clear : .regular
        if amount > 0.02 {
            let opacity = scheme == .dark
                ? 0.14 + amount * 0.50
                : 0.22 + amount * 0.50
            material = material.tint(glassTint.opacity(opacity))
        }
        if interactive {
            material = material.interactive()
        }
        return material
    }
    #endif
}

extension Pinboard {
    var color: Color {
        Color(hex: colorHex) ?? AppPalette.brand
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

private struct GlassTintAmountKey: EnvironmentKey {
    static let defaultValue: Double = 0.45
}

extension EnvironmentValues {
    var glassTintAmount: Double {
        get { self[GlassTintAmountKey.self] }
        set { self[GlassTintAmountKey.self] = newValue }
    }
}

struct AppBrandChromeModifier: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        content
            .environment(\.glassTintAmount, settings.glassTintAmount)
            .preferredColorScheme(settings.appearanceMode.colorScheme)
            .tint(AppPalette.controlOn)
    }
}

extension View {
    func appBrandChrome() -> some View {
        modifier(AppBrandChromeModifier())
    }
}
