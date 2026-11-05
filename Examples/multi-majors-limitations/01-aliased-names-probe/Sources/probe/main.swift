import LibOne
import LibTwo

// canImport only says the compiler can *find* a module. The section at the bottom actually imports and uses
// both majors directly from the root, which is the real test.
//
// Finding from the first attempt: the root's own bucket (Shared 2.x) is spelled `Shared`, because the build
// passes `-module-alias Shared=Shared_v2` and the compiler rejects `import Shared_v2` ("cannot refer to module
// as 'Shared_v2' because it has been aliased; use 'Shared' instead"). The other bucket is not in the root's
// alias set, so it is spelled by its renamed name, `Shared_v1`.
#if canImport(Shared_v1)
import Shared_v1
#endif
#if canImport(Shared)
import Shared
#endif

// canImport is evaluated at compile time, so this reports what the root's module search paths hold
// without the build failing when a name is missing.
#if canImport(Shared_v1)
let canImportV1 = "yes"
#else
let canImportV1 = "no"
#endif

#if canImport(Shared_v2)
let canImportV2 = "yes"
#else
let canImportV2 = "no"
#endif

#if canImport(Shared_v3)
let canImportV3 = "yes"
#else
let canImportV3 = "no"
#endif

#if canImport(Shared)
let canImportPlain = "yes"
#else
let canImportPlain = "no"
#endif

print("== names the root can import ==")
print("canImport(Shared_v1) = \(canImportV1)")
print("canImport(Shared_v2) = \(canImportV2)")
print("canImport(Shared_v3) = \(canImportV3)")
print("canImport(Shared)    = \(canImportPlain)")

print("\n== what the libraries were compiled against ==")
print("LibOne.sharedMajor = \(LibOne.sharedMajor)   (expected 1)")
print("LibTwo.sharedMajor = \(LibTwo.sharedMajor)   (expected 2)")

// The root never writes the name of Token, it just asks the runtime what module each one lives in.
// Expected: Shared_v1.Token and Shared_v2.Token, i.e. two distinct types.
print("\n== types the root receives through public API ==")
print("LibOne token type: \(String(reflecting: type(of: LibOne.makeToken("a"))))")
print("LibTwo token type: \(String(reflecting: type(of: LibTwo.makeToken("a"))))")

#if canImport(Shared_v1) && canImport(Shared)
// Names are module-qualified because both majors define SharedInfo and Token.
// `Shared` is the root's own bucket (2.x); `Shared_v1` is the one it did not declare.
print("\n== root uses both aliased modules directly ==")
print("Shared_v1.SharedInfo.major = \(Shared_v1.SharedInfo.major)   (expected 1)")
print("Shared.SharedInfo.major (2.x bucket) = \(Shared.SharedInfo.major)   (expected 2)")
print(Shared_v1.SharedInfo.legacyOnly())    // only exists in 1.x
print(Shared.SharedInfo.modernOnly())    // only exists in 2.x

// A token the ROOT builds from Shared_v1 is accepted by LibOne, which was compiled against the same module.
print(LibOne.describe(Shared_v1.Token("built in root")))
print(LibTwo.describe(Shared.Token("built in root")))

// Global state: if the majors are really separate modules each registry only has its own entries.
Shared_v1.SharedInfo.register("root")
Shared.SharedInfo.register("root")
print("v1 registry: \(Shared_v1.SharedInfo.registry)")
print("v2 registry: \(Shared.SharedInfo.registry)")
print("LibOne sees: \(LibOne.registerAndDump())   (expected to include v1:root and v1:LibOne, nothing from v2)")
#else
print("\nBoth aliased modules are not importable from the root; skipping direct use.")
#endif
