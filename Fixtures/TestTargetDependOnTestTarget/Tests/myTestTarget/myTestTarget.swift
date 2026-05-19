import Testing

@Suite
struct MyTestTargetTests {
    @Test("MyTestTarget tests")
    func example() {
        #expect(42 == 17 + 25)
    }
}
