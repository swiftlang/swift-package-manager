import Utils
// Note the lack of 'import Foundation'.
// The purpose of this fixture is to test that the following line of code
// expectedly *doesn't* compile:
print(FooUtils.foo.trimmingCharacters(in: .whitespaces))
