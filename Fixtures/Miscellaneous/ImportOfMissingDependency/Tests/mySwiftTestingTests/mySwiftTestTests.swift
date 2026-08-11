import Testing

@Suite
struct MySwiftTestTestsTests {
    @Test("MySwiftTestTests tests")
    func example() {
        #expect(42 == 17 + 25)
    }
}