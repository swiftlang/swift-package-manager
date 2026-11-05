import LibOne
import LibTwo

print("sharedMajor: \(LibOne.sharedMajor) \(LibTwo.sharedMajor)   (expected 1 2)")
print("token types: \(LibOne.tokenTypeName), \(LibTwo.tokenTypeName)   (expected Shared_v1.Token, Shared_v2.Token)")
print("LibOne log: \(LibOne.registerAndDump())")
print("LibTwo log: \(LibTwo.registerAndDump())   (expected only v2:LibTwo)")

// The root can still see both majors' types, but only as opaque values returned from library APIs.
print("root-visible token types: \(String(reflecting: type(of: LibOne.makeToken("x")))), \(String(reflecting: type(of: LibTwo.makeToken("x"))))")
