/// This file exists to test the ability to override deployment targets via args passed to swiftc
/// For this test to work, this file must have an API call which was introduced in a version
/// higher than the default macOS deployment target that is checked in.
@available(macOS 10.20, *)
func foo() {}

foo()
