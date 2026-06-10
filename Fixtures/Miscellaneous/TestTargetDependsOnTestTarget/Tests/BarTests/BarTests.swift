import TestUtils
import Testing

@Suite struct BarTests {
    @Test func example() {
        #expect(makeLib().value() == 42)
    }
}
