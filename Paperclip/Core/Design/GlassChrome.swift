import SwiftUI
import AppKit

/// Liquid Glass on macOS 26+, material fallback on 14–15.
///
/// Apple’s model: one window glass, interactive glass for chrome, tinted
/// content surfaces for readable rows. Tint amount follows `glassTintAmount`
/// (Clear → Tinted), matching iOS Appearance > Liquid Glass.
extension View {
    func appGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(AppGlassEffectModifier(shape: shape, interactive: interactive, preferClear: false))
    }

    func appGlassClear<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(AppGlassEffectModifier(shape: shape, interactive: interactive, preferClear: true))
    }

    func appContentSurface(selected: Bool = false) -> some View {
        modifier(AppContentSurfaceModifier(selected: selected))
    }

    func appControlGlass() -> some View {
        appGlass(
            in: RoundedRectangle(cornerRadius: AppTheme.radiusControl, style: .continuous),
            interactive: true
        )
    }

    func appCapsuleGlass(interactive: Bool = false) -> some View {
        appGlass(in: Capsule(), interactive: interactive)
    }

    func appIconGlass() -> some View {
        appGlass(in: Circle(), interactive: true)
    }

    func appWindowFill() -> some View {
        modifier(AppWindowFillModifier())
    }

    func appFloatingGlass() -> some View {
        modifier(AppFloatingGlassModifier())
    }

    @ViewBuilder
    func appWindowContainer() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.clear, for: .window)
        } else {
            self
        }
    }

    func appGlassButton() -> some View {
        self.buttonStyle(AppFilledButtonStyle(kind: .brand))
    }

    func appGlassProminentButton() -> some View {
        self.buttonStyle(AppFilledButtonStyle(kind: .accent))
    }

    func appDangerButton() -> some View {
        self.buttonStyle(AppFilledButtonStyle(kind: .danger))
    }

    func appPreferencesChrome() -> some View {
        self
            .formStyle(.grouped)
            .toggleStyle(AppSwitchToggleStyle())
            .tint(AppPalette.controlOn)
            .scrollContentBackground(.hidden)
            .padding(AppTheme.spaceS)
    }

    func appListChrome() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
    }
}

/// Opaque surfaces instead of Liquid Glass. On when the user enables "Reduce transparency"
/// in System Settings › Accessibility, or when set explicitly (offscreen previews, tests).
private struct AppGlassDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appGlassDisabled: Bool {
        get { self[AppGlassDisabledKey.self] }
        set { self[AppGlassDisabledKey.self] = newValue }
    }
}

private struct AppGlassEffectModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive: Bool
    var preferClear: Bool
    @Environment(\.glassTintAmount) private var tintAmount
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appGlassDisabled) private var glassDisabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if glassDisabled || reduceTransparency {
            content
                .background(shape.fill(AppPalette.surface))
                .overlay(shape.strokeBorder(AppPalette.stroke, lineWidth: 0.6))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    AppPalette.glass(
                        tintAmount: tintAmount,
                        interactive: interactive,
                        clearBias: preferClear,
                        scheme: colorScheme
                    ),
                    in: shape
                )
            } else {
                material(content)
            }
            #else
            material(content)
            #endif
        }
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(AppPalette.glassTint.opacity(0.04 + tintAmount * 0.14)))
            .overlay(shape.strokeBorder(AppPalette.stroke, lineWidth: 0.6))
    }
}

private struct AppContentSurfaceModifier: ViewModifier {
    var selected: Bool
    @Environment(\.glassTintAmount) private var tintAmount
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous)
        let fill: Color = {
            if selected { return AppPalette.surfaceSelected }
            if colorScheme == .light {
                return AppPalette.white.opacity(0.78 + tintAmount * 0.16)
            }
            return AppPalette.navyDeep.opacity(0.28 + tintAmount * 0.22)
        }()
        return content
            .background(shape.fill(fill))
            .overlay(
                shape.strokeBorder(
                    selected ? AppPalette.gold.opacity(0.85) : AppPalette.stroke,
                    lineWidth: selected ? 1.5 : 0.6
                )
            )
    }
}

private struct AppWindowFillModifier: ViewModifier {
    @Environment(\.glassTintAmount) private var tintAmount
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appGlassDisabled) private var glassDisabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let wash = colorScheme == .light
            ? AppPalette.white.opacity(0.18 + tintAmount * 0.36)
            : AppPalette.midnight.opacity(0.04 + tintAmount * 0.14)
        if glassDisabled || reduceTransparency {
            content.background(AppPalette.canvas)
        } else if #available(macOS 26.0, *) {
            // The window itself is NSGlassEffectView on macOS 26; only a wash is needed here.
            content.background(wash)
        } else {
            content.background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    wash
                }
            }
        }
    }
}

private struct AppFloatingGlassModifier: ViewModifier {
    @Environment(\.glassTintAmount) private var tintAmount
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appGlassDisabled) private var glassDisabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.radiusWindow, style: .continuous)
        if glassDisabled || reduceTransparency {
            content
                .background(shape.fill(AppPalette.canvas))
                .overlay(shape.strokeBorder(AppPalette.stroke, lineWidth: 0.6))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    AppPalette.glass(tintAmount: tintAmount, interactive: false, scheme: colorScheme),
                    in: shape
                )
            } else {
                material(content, shape: shape)
            }
            #else
            material(content, shape: shape)
            #endif
        }
    }

    private func material(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(AppPalette.glassTint.opacity(0.05 + tintAmount * 0.18)))
    }
}

enum AppGlass {
    static var stroke: Color { AppPalette.stroke }
    static var highlight: Color { AppPalette.highlight }
    static var chipFill: Color { AppPalette.chipFill }
}

struct AppFilledButtonStyle: ButtonStyle {
    enum Kind {
        case brand
        case accent
        case danger
    }

    var kind: Kind = .accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.calloutMedium)
            .padding(.horizontal, AppTheme.buttonPadH)
            .padding(.vertical, AppTheme.buttonPadV)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusControl, style: .continuous)
                    .fill(background.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusControl, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: background.opacity(configuration.isPressed ? 0.12 : 0.35), radius: 4, y: 1)
    }

    private var background: Color {
        switch kind {
        case .brand: return AppPalette.brand
        case .accent: return AppPalette.goldBright
        case .danger: return AppPalette.danger
        }
    }

    private var foreground: Color {
        switch kind {
        case .brand, .accent: return AppPalette.onAccent
        case .danger: return AppPalette.onDanger
        }
    }

    private var border: Color {
        switch kind {
        case .brand: return AppPalette.brandDeep
        case .accent: return AppPalette.gold
        case .danger: return AppPalette.danger.opacity(0.85)
        }
    }
}

struct AppSwitch: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? AppPalette.controlOn : AppPalette.switchOff)
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? AppPalette.gold : AppPalette.stroke, lineWidth: 1.25)
            )
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? AppPalette.midnight : AppPalette.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 44, height: 26)
            .animation(.snappy(duration: 0.16), value: isOn)
            .accessibilityAddTraits(.isToggle)
    }
}

struct AppSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: AppTheme.spaceS) {
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: AppTheme.spaceS)
                AppSwitch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct AppGlassCluster<Content: View>: View {
    var spacing: CGFloat = AppTheme.spaceS
    @ViewBuilder var content: () -> Content
    @Environment(\.appGlassDisabled) private var glassDisabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if glassDisabled || reduceTransparency {
            HStack(spacing: AppTheme.spaceXS, content: content)
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    HStack(spacing: AppTheme.spaceXS, content: content)
                }
            } else {
                HStack(spacing: AppTheme.spaceXS, content: content)
            }
            #else
            HStack(spacing: AppTheme.spaceXS, content: content)
            #endif
        }
    }
}

struct AppEmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppTheme.spaceS) {
            Image(systemName: systemImage)
                .font(AppTheme.symbolLarge)
                .foregroundStyle(AppPalette.brand.opacity(0.75))
            Text(title)
                .font(AppTheme.headline)
            Text(subtitle)
                .font(AppTheme.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AppTheme.emptyMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.spaceXL)
    }
}

struct AppChip: View {
    let title: String
    var systemImage: String? = nil
    var foreground: Color = AppPalette.slate
    var fill: Color = AppPalette.chipFill
    var onClear: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppTheme.spaceXXS) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppTheme.caption2Semibold)
            }
            Text(title)
                .font(AppTheme.captionMedium)
                .lineLimit(1)
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(AppTheme.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, AppTheme.chipPadH)
        .padding(.vertical, AppTheme.chipPadV)
        .background(Capsule().fill(fill))
    }
}

struct LiquidGlassPreview: View {
    var body: some View {
        HStack(spacing: AppTheme.spaceS) {
            HStack(spacing: AppTheme.spaceS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppPalette.brand)
                Text("Search")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.spaceM)
            .padding(.vertical, AppTheme.spaceS)
            .appControlGlass()

            Button("Done") {}
                .buttonStyle(AppFilledButtonStyle(kind: .brand))
        }
        .allowsHitTesting(false)
    }
}

extension NSWindow {
    func applyAppGlassChrome() {
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        hasShadow = true
        contentView?.wantsLayer = true
        contentView?.layer?.isOpaque = false
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func applyAppColorScheme(_ mode: AppearanceMode) {
        appearance = mode.nsAppearance
    }

    func applyAppGlassTint(amount: Double) {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *), let glass = contentView as? NSGlassEffectView else { return }
        AppPalette.applyWindowGlass(
            glass,
            tintAmount: amount,
            appearance: appearance ?? effectiveAppearance
        )
        #endif
    }

    /// Embeds SwiftUI content in AppKit Liquid Glass so the panel samples the desktop.
    func setAppGlassContentView(_ view: NSView, tintAmount: Double) {
        applyAppGlassChrome()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = AppTheme.radiusWindow
            glass.setFrameSize(view.frame.size)
            view.autoresizingMask = [.width, .height]
            glass.contentView = view
            AppPalette.applyWindowGlass(
                glass,
                tintAmount: tintAmount,
                appearance: appearance ?? effectiveAppearance
            )
            contentView = glass
        } else {
            contentView = view
        }
        #else
        contentView = view
        #endif

        applyAppGlassChrome()
    }
}
