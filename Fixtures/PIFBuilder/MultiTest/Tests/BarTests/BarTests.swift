import Testing
import MultiTest

@Suite
struct BarTests {
    @Test
    func answerIsNotZero() {
        #expect(MultiTest().answer() != 0)
    }
}
