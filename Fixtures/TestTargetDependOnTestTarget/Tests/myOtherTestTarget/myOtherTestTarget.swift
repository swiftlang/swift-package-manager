import Testing

@Suite
struct MyOTherTestTargetTests {
    @Test("MyOTherTestTarget tests")
    func example() {
        #expect(42 == 17 + 25)
    }
}
