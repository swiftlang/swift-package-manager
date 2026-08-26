import Testing
@testable import LibA

@Test
func libAGreeting_returnsExpected() {
    #expect(libAGreeting() == "Hello from lib-a")
}
