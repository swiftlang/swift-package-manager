import Vapor

public struct EmailAddress: Hashable, Sendable {
    public let value: String

    public init?(_ raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()

        let result = Validator<String>.email.validate(normalized)
        guard !result.isFailure else { return nil }

        self.value = normalized
    }
}