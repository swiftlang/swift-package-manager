import Testing

// This test exists to force xunit to report at least one test pass
// for systems that require the output to report something.
struct PhonyTest {
    @Test func phonyPass() {}
}
