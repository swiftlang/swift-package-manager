import Testing
@testable import LibB

@Test
func libBGreeting_returnsExpected() {
    #expect(libBGreeting() == "Hello from lib-b")
}
