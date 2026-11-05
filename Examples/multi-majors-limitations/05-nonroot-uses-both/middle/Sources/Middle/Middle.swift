import LibOne

// Same probe as example 01, but compiled as a dependency rather than as the root.
// The package's own bucket is spelled `Shared` (-module-alias Shared=Shared_v2); `import Shared_v2` is rejected.
#if canImport(Shared)
import Shared
let v2Import = "Shared (its own bucket)"
#else
let v2Import = "NONE"
#endif

#if canImport(Shared_v1)
let canImportV1 = "yes"
#else
let canImportV1 = "no"
#endif

public enum Middle {
    public static func report() -> String {
        var lines = [
            "Middle imported its own Shared as: \(v2Import)",
            "Middle canImport(Shared_v1): \(canImportV1)",
            "LibOne.sharedMajor (v1 expected): \(LibOne.sharedMajor)",
        ]
        #if canImport(Shared)
        lines.append("Middle's own SharedInfo.major (v2 expected): \(SharedInfo.major)")
        #endif
        return lines.joined(separator: "\n")
    }
}
