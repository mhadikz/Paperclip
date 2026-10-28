import Foundation

/// A named collection of clip IDs. Stores references only — never clip bodies.
struct Pinboard: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var clipIDs: [UUID]
    var createdAt: Date

    /// Gold — the brand accent.
    static let defaultColorHex = "#FFC300"

    /// Hues that stay legible on both the frosted-white Light canvas and midnight Dark glass.
    static let colorPalette: [String] = [
        "#FFC300", // gold
        "#FF6B6B", // coral
        "#2EC4B6", // teal
        "#4CC9F0", // sky
        "#9D4EDD", // violet
        "#A7C957"  // lime
    ]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = Pinboard.defaultColorHex,
        clipIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.clipIDs = clipIDs
        self.createdAt = createdAt
    }
}
