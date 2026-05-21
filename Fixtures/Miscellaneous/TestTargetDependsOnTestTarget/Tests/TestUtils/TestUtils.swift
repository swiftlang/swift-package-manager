@testable import MyLib
import Testing

// Shared test helpers used by FooTests and BarTests.
package func makeLib() -> MyLib { MyLib() }
