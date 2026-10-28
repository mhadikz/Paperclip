import Foundation

@MainActor
func registerSensitiveContentTests(_ r: TestRunner) {
    r.test("sensitive: private key block") {
        try expect(SensitiveContentFilter.looksSensitive("-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----"), "private key")
        try expect(SensitiveContentFilter.looksSensitive("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk=\n-----END OPENSSH PRIVATE KEY-----"), "openssh key")
    }

    r.test("sensitive: JWT") {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturepart"
        try expect(SensitiveContentFilter.looksSensitive(jwt), "JWT should be sensitive")
        try expect(!SensitiveContentFilter.looksSensitive("eyJ is how a JWT starts, said the article."), "prose mentioning eyJ is fine")
    }

    r.test("sensitive: secret markers and known prefixes") {
        // Fixtures are assembled at runtime so secret scanners never see a literal token shape.
        func token(_ prefix: String, _ body: String) -> String { prefix + body }
        try expect(SensitiveContentFilter.looksSensitive("DB_PASSWORD=hunter2hunter2"), "password=")
        try expect(SensitiveContentFilter.looksSensitive("Authorization: Bearer abc.def.ghi"), "bearer")
        try expect(SensitiveContentFilter.looksSensitive(token("sk-proj-", "AbCdEf1234567890GhIjKlMnOpQrStUv")), "openai key")
        try expect(SensitiveContentFilter.looksSensitive(token("ghp_", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")), "github token")
        try expect(SensitiveContentFilter.looksSensitive(token("AKIA", "IOSFODNN7EXAMPLE")), "aws key id")
        try expect(SensitiveContentFilter.looksSensitive(token("xoxb-", "123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx")), "slack token")
    }

    r.test("sensitive: card numbers need a contiguous run") {
        try expect(SensitiveContentFilter.looksSensitive("4111 1111 1111 1111"), "visa test number")
        try expect(SensitiveContentFilter.looksSensitive("Card: 5500-0000-0000-0004 exp 12/28"), "mastercard with dashes")
        try expect(!SensitiveContentFilter.looksSensitive("Order 4111 shipped 1111 units on 11/11, ref 1111"), "scattered digits")
        try expect(!SensitiveContentFilter.looksSensitive("Meeting 2026-10-26 at 14:30, room 1204, ticket 55321"), "dates and numbers")
    }

    r.test("sensitive: ordinary developer strings are not secrets") {
        let safe = [
            "https://example.com/some/long/path?query=1&other=abcdefgh12345",
            "first.last@example-company.com",
            "/Users/sam/Projects/Paperclip/App/DependencyContainer.swift",
            "~/Library/Application Support/Paperclip/history.json",
            "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
            "NSApplicationDelegateReplyFailureInternalError2",
            "com.apple.security.temporary-exception.files.home-relative-path.read-only",
            "git@github.com:org/repo.git",
            "The quick brown fox jumps over the lazy dog 1234567890 times.",
            "+1 (415) 555-0132",
            "docker run -it --rm -p 8080:80 nginx:1.27-alpine"
        ]
        for value in safe {
            try expect(!SensitiveContentFilter.looksSensitive(value), "should be safe: \(value)")
        }
    }

    r.test("sensitive: opaque mixed-class tokens are caught") {
        try expect(SensitiveContentFilter.looksSensitive("Qz9xT3bL8mN2vK7pR4wS6yU1aH5jD0fG"), "random token")
        try expect(!SensitiveContentFilter.looksSensitive("ThisIsJustALongCamelCaseIdentifierName"), "no digits → identifier")
    }

    r.test("sensitive: redacted placeholder names the kind") {
        try expectEqual(SensitiveContentFilter.redactedPlaceholder(for: "-----BEGIN PRIVATE KEY-----"), "[redacted private key]")
        try expectEqual(SensitiveContentFilter.redactedPlaceholder(for: "4111 1111 1111 1111"), "[redacted card number]")
        try expectEqual(SensitiveContentFilter.redactedPlaceholder(for: "api_key=xyz"), "[redacted secret]")
    }
}
