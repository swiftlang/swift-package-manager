import Testing

@Suite
struct LeafTestTargetTests {
    @Test("LeafTestTarget tests")
    func example() {
        #expect(42 == 17 + 25)
    }
}