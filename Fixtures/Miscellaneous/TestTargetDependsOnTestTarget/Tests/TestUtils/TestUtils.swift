@testable import MyLib
import Testing

// Shared test helpers used by FooTests and BarTests.
func makeLib() -> MyLib { MyLib() }
