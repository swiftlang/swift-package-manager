import Testing
import MultiTest

@Suite
struct FooTests {
    @Test
    func answerIsFortyTwo() {
        #expect(MultiTest().answer() == 42)
    }
}
