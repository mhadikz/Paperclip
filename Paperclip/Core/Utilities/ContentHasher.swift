import Foundation
import CryptoKit

enum ContentHasher {
    /// Hex SHA-256 of the payload. Used to collapse identical image copies into one clip.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
