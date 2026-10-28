import Foundation
import Combine

/// User preferences backed by `UserDefaults`. Pure state: side effects (login item
/// registration, hotkey registration, window privacy) are performed by services that
/// observe the notifications posted here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: - Clipboard

    @Published var rememberCount: Int {
        didSet {
            let clamped = min(max(rememberCount, Limits.minRemember), Limits.maxRemember)
            if clamped != rememberCount { rememberCount = clamped; return }
            defaults.set(clamped, forKey: Keys.rememberCount)
        }
    }

    @Published var displayCount: Int {
        didSet {
            let clamped = min(max(displayCount, Limits.minDisplay), Limits.maxDisplay)
            if clamped != displayCount { displayCount = clamped; return }
            defaults.set(clamped, forKey: Keys.displayCount)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            NotificationCenter.default.post(name: .clipboardLaunchAtLoginChanged, object: nil)
        }
    }

    @Published var recordHistory: Bool {
        didSet { defaults.set(recordHistory, forKey: Keys.recordHistory) }
    }

    @Published var confirmBeforeDeleting: Bool {
        didSet { defaults.set(confirmBeforeDeleting, forKey: Keys.confirmBeforeDeleting) }
    }

    @Published var skipSensitiveContent: Bool {
        didSet { defaults.set(skipSensitiveContent, forKey: Keys.skipSensitiveContent) }
    }

    @Published var hideFromScreenSharing: Bool {
        didSet {
            defaults.set(hideFromScreenSharing, forKey: Keys.hideFromScreenSharing)
            NotificationCenter.default.post(name: .clipboardPrivacyChanged, object: nil)
        }
    }

    /// Paste into the frontmost app after choosing a clip (needs Accessibility).
    @Published var pasteAndEnter: Bool {
        didSet { defaults.set(pasteAndEnter, forKey: Keys.pasteAndEnter) }
    }

    /// Keep an RTF sidecar for formatted text so paste restores bold/links/colors.
    @Published var captureRichText: Bool {
        didSet { defaults.set(captureRichText, forKey: Keys.captureRichText) }
    }

    @Published var hotKey: HotKeySpec {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            }
            NotificationCenter.default.post(name: .clipboardHotKeyChanged, object: nil)
        }
    }

    @Published var ignoredBundleIDs: Set<String> {
        didSet { defaults.set(Array(ignoredBundleIDs).sorted(), forKey: Keys.ignoredBundleIDs) }
    }

    // MARK: - Appearance

    /// 0 = Clear Liquid Glass, 1 = Tinted. Matches iOS Appearance > Liquid Glass.
    @Published var glassTintAmount: Double {
        didSet {
            let clamped = min(max(glassTintAmount, 0), 1)
            if clamped != glassTintAmount { glassTintAmount = clamped; return }
            defaults.set(clamped, forKey: Keys.glassTintAmount)
            NotificationCenter.default.post(name: .clipboardAppearanceChanged, object: nil)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            NotificationCenter.default.post(name: .clipboardAppearanceChanged, object: nil)
        }
    }

    // MARK: - AI

    @Published var aiFeaturesEnabled: Bool {
        didSet { defaults.set(aiFeaturesEnabled, forKey: Keys.aiFeaturesEnabled) }
    }

    @Published var automaticAIProcessing: Bool {
        didSet { defaults.set(automaticAIProcessing, forKey: Keys.automaticAIProcessing) }
    }

    @Published var automaticSummaries: Bool {
        didSet { defaults.set(automaticSummaries, forKey: Keys.automaticSummaries) }
    }

    @Published var automaticTags: Bool {
        didSet { defaults.set(automaticTags, forKey: Keys.automaticTags) }
    }

    @Published var semanticSearch: Bool {
        didSet { defaults.set(semanticSearch, forKey: Keys.semanticSearch) }
    }

    @Published var processSensitiveContent: Bool {
        didSet { defaults.set(processSensitiveContent, forKey: Keys.processSensitiveContent) }
    }

    @Published var useFoundationModels: Bool {
        didSet { defaults.set(useFoundationModels, forKey: Keys.useFoundationModels) }
    }

    @Published var sensitiveStoragePolicy: SensitiveStoragePolicy {
        didSet { defaults.set(sensitiveStoragePolicy.rawValue, forKey: Keys.sensitiveStoragePolicy) }
    }

    // MARK: - Limits

    enum Limits {
        static let minRemember = 1
        static let maxRemember = 100_000
        static let minDisplay = 1
        static let maxDisplay = 50
    }

    enum Keys {
        static let rememberCount = "rememberCount"
        static let displayCount = "displayCount"
        static let launchAtLogin = "launchAtLogin"
        static let recordHistory = "recordHistory"
        static let confirmBeforeDeleting = "confirmBeforeDeleting"
        static let skipSensitiveContent = "skipSensitiveContent"
        static let hideFromScreenSharing = "hideFromScreenSharing"
        static let pasteAndEnter = "pasteAndEnter"
        static let captureRichText = "captureRichText"
        static let hotKey = "hotKey"
        static let glassTintAmount = "glassTintAmount"
        static let appearanceMode = "appearanceMode"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let aiFeaturesEnabled = "aiFeaturesEnabled"
        static let automaticAIProcessing = "automaticAIProcessing"
        static let automaticSummaries = "automaticSummaries"
        static let automaticTags = "automaticTags"
        static let semanticSearch = "semanticSearch"
        static let processSensitiveContent = "processSensitiveContent"
        static let useFoundationModels = "useFoundationModels"
        static let sensitiveStoragePolicy = "sensitiveStoragePolicy"
    }

    // MARK: - Init

    /// Defaults domains used by earlier builds, newest first. Settings found there are copied once.
    static let legacyDefaultsSuites = ["com.local.Clipboard"]
    private static let migrationKey = "migratedLegacyDefaults"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        rememberCount = min(max(defaults.object(forKey: Keys.rememberCount) as? Int ?? 1000, Limits.minRemember), Limits.maxRemember)
        displayCount = min(max(defaults.object(forKey: Keys.displayCount) as? Int ?? 20, Limits.minDisplay), Limits.maxDisplay)

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        recordHistory = Self.bool(defaults, Keys.recordHistory, default: true)
        confirmBeforeDeleting = Self.bool(defaults, Keys.confirmBeforeDeleting, default: true)
        skipSensitiveContent = Self.bool(defaults, Keys.skipSensitiveContent, default: true)
        hideFromScreenSharing = defaults.bool(forKey: Keys.hideFromScreenSharing)
        pasteAndEnter = Self.bool(defaults, Keys.pasteAndEnter, default: true)
        captureRichText = Self.bool(defaults, Keys.captureRichText, default: true)

        if let data = defaults.data(forKey: Keys.hotKey),
           let spec = try? JSONDecoder().decode(HotKeySpec.self, from: data),
           spec.isValid {
            hotKey = spec
        } else {
            hotKey = .default
        }

        if defaults.object(forKey: Keys.glassTintAmount) != nil {
            glassTintAmount = min(max(defaults.double(forKey: Keys.glassTintAmount), 0), 1)
        } else {
            glassTintAmount = 0.45
        }

        if let raw = defaults.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }

        ignoredBundleIDs = Set(defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? [])

        aiFeaturesEnabled = Self.bool(defaults, Keys.aiFeaturesEnabled, default: true)
        automaticAIProcessing = Self.bool(defaults, Keys.automaticAIProcessing, default: true)
        automaticSummaries = Self.bool(defaults, Keys.automaticSummaries, default: true)
        automaticTags = Self.bool(defaults, Keys.automaticTags, default: true)
        semanticSearch = Self.bool(defaults, Keys.semanticSearch, default: true)
        processSensitiveContent = defaults.bool(forKey: Keys.processSensitiveContent)
        useFoundationModels = Self.bool(defaults, Keys.useFoundationModels, default: true)

        if let raw = defaults.string(forKey: Keys.sensitiveStoragePolicy),
           let policy = SensitiveStoragePolicy(rawValue: raw) {
            sensitiveStoragePolicy = policy
        } else {
            sensitiveStoragePolicy = .neverStore
        }
    }

    /// Copies known keys from the domains of earlier bundle identifiers the first time the new domain
    /// is seen, so renaming the app does not reset the user's preferences. Newer domains win.
    static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard defaults.object(forKey: migrationKey) == nil else { return }
        defaults.set(true, forKey: migrationKey)
        guard defaults === UserDefaults.standard,
              let bundleID = Bundle.main.bundleIdentifier,
              !legacyDefaultsSuites.contains(bundleID) else { return }
        let known: [String] = [
            Keys.rememberCount, Keys.displayCount, Keys.launchAtLogin, Keys.recordHistory,
            Keys.confirmBeforeDeleting, Keys.skipSensitiveContent, Keys.hideFromScreenSharing,
            Keys.pasteAndEnter, Keys.captureRichText, Keys.hotKey, Keys.glassTintAmount, Keys.appearanceMode,
            Keys.ignoredBundleIDs, Keys.aiFeaturesEnabled, Keys.automaticAIProcessing, Keys.automaticSummaries,
            Keys.automaticTags, Keys.semanticSearch, Keys.processSensitiveContent, Keys.useFoundationModels,
            Keys.sensitiveStoragePolicy
        ]
        var copied = 0
        for suite in legacyDefaultsSuites {
            guard let legacy = UserDefaults.standard.persistentDomain(forName: suite), !legacy.isEmpty else { continue }
            for key in known where defaults.object(forKey: key) == nil {
                if let value = legacy[key] {
                    defaults.set(value, forKey: key)
                    copied += 1
                }
            }
        }
        if copied > 0 {
            AppLogger.event("Migrated \(copied) settings from a previous bundle identifier")
        }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    // MARK: - Derived

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            aiFeaturesEnabled: aiFeaturesEnabled,
            automaticAIProcessing: automaticAIProcessing,
            automaticSummaries: automaticSummaries,
            automaticTags: automaticTags,
            semanticSearch: semanticSearch,
            processSensitiveContent: processSensitiveContent,
            useFoundationModels: useFoundationModels,
            sensitiveStoragePolicy: sensitiveStoragePolicy
        )
    }

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredBundleIDs.contains(bundleID)
    }

    func toggleIgnored(bundleID: String) {
        if ignoredBundleIDs.contains(bundleID) {
            ignoredBundleIDs.remove(bundleID)
        } else {
            ignoredBundleIDs.insert(bundleID)
        }
    }
}

extension Notification.Name {
    static let clipboardPrivacyChanged = Notification.Name("clipboardPrivacyChanged")
    static let clipboardAppearanceChanged = Notification.Name("clipboardAppearanceChanged")
    static let clipboardHotKeyChanged = Notification.Name("clipboardHotKeyChanged")
    static let clipboardLaunchAtLoginChanged = Notification.Name("clipboardLaunchAtLoginChanged")
}
