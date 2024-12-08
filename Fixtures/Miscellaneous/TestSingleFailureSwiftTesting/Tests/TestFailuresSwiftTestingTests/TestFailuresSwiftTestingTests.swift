import Testing
@testable import TestFailuresSwiftTesting

@Test func example() async throws {
    #expect(Bool(false), "Purposely failing & validating XML espace \"'<>")
}
