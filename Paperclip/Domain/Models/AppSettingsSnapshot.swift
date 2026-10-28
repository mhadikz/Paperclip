import Foundation

/// Immutable, `Sendable` copy of the AI-related settings for background work.
struct AppSettingsSnapshot: Sendable, Equatable {
    var aiFeaturesEnabled: Bool
    var automaticAIProcessing: Bool
    var automaticSummaries: Bool
    var automaticTags: Bool
    var semanticSearch: Bool
    var processSensitiveContent: Bool
    var useFoundationModels: Bool
    var sensitiveStoragePolicy: SensitiveStoragePolicy
}
