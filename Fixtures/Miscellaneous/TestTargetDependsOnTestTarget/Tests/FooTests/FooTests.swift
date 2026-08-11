import TestUtils
import Testing

@Suite struct FooTests {
    @Test func example() {
        #expect(makeLib().value() == 42)
    }
}
