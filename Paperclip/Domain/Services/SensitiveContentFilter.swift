import Foundation

/// Heuristics that decide whether captured text is probably a secret.
///
/// Precision matters more than recall here: a false positive silently drops something the
/// user copied on purpose (a file path, an identifier, a commit hash), which is worse than
/// storing a token in a local history that already lives next to the system pasteboard.
enum SensitiveContentFilter {
    static func looksSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200_000 else { return false }

        if containsPrivateKeyBlock(trimmed) { return true }
        if looksLikeJWT(trimmed) { return true }
        if containsSecretMarker(trimmed) { return true }
        if looksLikeCardNumber(trimmed) { return true }
        if hasKnownSecretPrefix(trimmed) { return true }
        if looksLikeOpaqueToken(trimmed) { return true }
        return false
    }

    static func redactedPlaceholder(for text: String) -> String {
        let kind: String
        if containsPrivateKeyBlock(text) { kind = "private key" }
        else if looksLikeJWT(text.trimmingCharacters(in: .whitespacesAndNewlines)) { kind = "JWT" }
        else if text.lowercased().contains("bearer") { kind = "auth token" }
        else if looksLikeCardNumber(text) { kind = "card number" }
        else { kind = "secret" }
        return "[redacted \(kind)]"
    }

    // MARK: - Detectors

    private static func containsPrivateKeyBlock(_ text: String) -> Bool {
        guard text.contains("-----BEGIN") else { return false }
        let upper = text.uppercased()
        return upper.contains("PRIVATE KEY") || upper.contains("BEGIN OPENSSH") || upper.contains("BEGIN PGP PRIVATE")
    }

    private static func looksLikeJWT(_ text: String) -> Bool {
        guard text.hasPrefix("eyJ"), text.count > 40, !text.contains(where: \.isWhitespace) else { return false }
        let parts = text.split(separator: ".")
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty }
    }

    private static let secretMarkers: [String] = [
        "password=", "password:", "passwd=", "pwd=", "secret=", "api_key=", "apikey=", "api-key=",
        "access_token=", "auth_token=", "private_key=", "client_secret=", "refresh_token=",
        "authorization: bearer", "x-api-key:", "aws_secret_access_key", "-----begin"
    ]

    private static func containsSecretMarker(_ text: String) -> Bool {
        let lower = text.lowercased()
        return secretMarkers.contains { lower.contains($0) }
    }

    /// Well-known credential formats (high precision, independent of entropy).
    private static let knownPrefixes: [String] = [
        "sk-",        // OpenAI-style
        "sk_live_", "sk_test_", "pk_live_", "rk_live_", // Stripe
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_",
        "glpat-",     // GitLab
        "xoxb-", "xoxp-", "xoxa-", "xoxr-", // Slack
        "AKIA", "ASIA", // AWS access key IDs
        "AIza",       // Google API
        "ya29.",      // Google OAuth
        "shpat_", "shpss_", // Shopify
        "npm_",       // npm
        "dop_v1_",    // DigitalOcean
        "hf_",        // Hugging Face
        "pypi-AgEIcHlwaS5vcmc" // PyPI
    ]

    private static func hasKnownSecretPrefix(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), text.count >= 16, text.count <= 512 else { return false }
        for prefix in knownPrefixes where text.hasPrefix(prefix) {
            // Require a token body made of the usual key alphabet after the prefix.
            let body = text.dropFirst(prefix.count)
            return body.count >= 10 && body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        }
        return false
    }

    /// 13–19 digits in one contiguous run (spaces or dashes allowed between groups) that pass Luhn.
    /// Scanning every digit in a paragraph would flag dates and phone numbers by chance.
    static func looksLikeCardNumber(_ text: String) -> Bool {
        guard text.count <= 64 else { return containsCardRun(in: text) }
        return containsCardRun(in: text)
    }

    private static func containsCardRun(in text: String) -> Bool {
        var run: [Int] = []
        var lastWasSeparator = false
        func check() -> Bool { run.count >= 13 && run.count <= 19 && luhnValid(run) }
        for ch in text {
            if let value = ch.wholeNumberValue, ch.isASCII {
                run.append(value)
                lastWasSeparator = false
            } else if (ch == " " || ch == "-") && !run.isEmpty && !lastWasSeparator {
                lastWasSeparator = true
            } else {
                if check() { return true }
                run.removeAll()
                lastWasSeparator = false
            }
        }
        return check()
    }

    private static func luhnValid(_ digits: [Int]) -> Bool {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            var value = digit
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    /// A single high-entropy token with mixed character classes. Paths, URLs, emails, UUIDs,
    /// hex digests and plain identifiers are explicitly exempt.
    private static func looksLikeOpaqueToken(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), text.count >= 24, text.count <= 128 else { return false }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://") { return false }
        if text.contains("@") || text.contains("/") || text.hasPrefix("~") || text.hasPrefix(".") { return false }
        if isUUID(text) || isHex(text) { return false }

        var lowers = 0, uppers = 0, digits = 0, symbols = 0
        for ch in text {
            if ch.isLowercase { lowers += 1 }
            else if ch.isUppercase { uppers += 1 }
            else if ch.isNumber { digits += 1 }
            else { symbols += 1 }
        }
        let classes = [lowers, uppers, digits, symbols].filter { $0 > 0 }.count
        guard classes >= 3 else { return false }
        guard Double(digits) / Double(text.count) >= 0.15 else { return false }
        // Identifiers such as `NSApplicationDelegateReply2` have few digits and read as words.
        return entropyScore(text) >= 3.9
    }

    private static func isUUID(_ text: String) -> Bool {
        text.count == 36 && UUID(uuidString: text) != nil
    }

    private static func isHex(_ text: String) -> Bool {
        let hex = text.hasPrefix("0x") ? text.dropFirst(2) : Substring(text)
        return !hex.isEmpty && hex.allSatisfy(\.isHexDigit)
    }

    private static func entropyScore(_ string: String) -> Double {
        var counts: [Character: Double] = [:]
        for char in string {
            counts[char, default: 0] += 1
        }
        let length = Double(string.count)
        return counts.values.reduce(0) { partial, count in
            let p = count / length
            return partial - (p * log2(p))
        }
    }
}
