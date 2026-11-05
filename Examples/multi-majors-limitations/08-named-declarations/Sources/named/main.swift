// Both majors are imported by their renamed names. If the build instead passes a `-module-alias Shared=...` for
// one of them, the compiler rejects that spelling ("use 'Shared' instead"); see example 01.
import Shared_v1
import Shared_v2

print("Shared_v1.SharedInfo.major = \(Shared_v1.SharedInfo.major)   (expected 1)")
print("Shared_v2.SharedInfo.major = \(Shared_v2.SharedInfo.major)   (expected 2)")
print(Shared_v1.SharedInfo.legacyOnly())
print(Shared_v2.SharedInfo.modernOnly())

Shared_v1.SharedInfo.register("root")
Shared_v2.SharedInfo.register("root")
print("v1 registry: \(Shared_v1.SharedInfo.registry)   (expected [v1:root])")
print("v2 registry: \(Shared_v2.SharedInfo.registry)   (expected [v2:root])")
print("v1 token type: \(String(reflecting: Shared_v1.Token.self))")
print("v2 token type: \(String(reflecting: Shared_v2.Token.self))")
