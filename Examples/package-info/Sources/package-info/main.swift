import PackageModel
import PackageLoading
import PackageGraph
import Workspace

// PREREQUISITES
// ============

// We will need to know where the Swift compiler is.
let swiftCompiler: AbsolutePath = {
    let string: String
    #if os(macOS)
    string = try! Process.checkNonZeroExit(args: "xcrun", "--sdk", "macosx", "-f", "swiftc").spm_chomp()
    #else
    string = try! Process.checkNonZeroExit(args: "which", "swiftc").spm_chomp()
    #endif
    return AbsolutePath(string)
}()

// We need a package to work with.
// This assumes there is one in the current working directory:
let packagePath = localFileSystem.currentWorkingDirectory!

// LOADING
// =======

// Note:
// This simplified API has been added since 0.4.0 was released.
// See older revisions for examples that work with 0.4.0.

// There are several levels of information available.
// Each takes longer to load than the level above it, but provides more detail.
let diagnostics = DiagnosticsEngine()
let identityResolver = DefaultIdentityResolver()
let manifest = try tsc_await { ManifestLoader.loadRootManifest(at: packagePath, swiftCompiler: swiftCompiler, swiftCompilerFlags: [], identityResolver: identityResolver, on: .global(), completion: $0) }
let loadedPackage = try tsc_await { PackageBuilder.loadRootPackage(at: packagePath, swiftCompiler: swiftCompiler, swiftCompilerFlags: [], identityResolver: identityResolver, diagnostics: diagnostics, on: .global(), completion: $0) }
let graph = try Workspace.loadRootGraph(at: packagePath, swiftCompiler: swiftCompiler, swiftCompilerFlags: [], identityResolver: identityResolver, diagnostics: diagnostics)

// EXAMPLES
// ========

// Manifest
let products = manifest.products.map({ $0.name }).joined(separator: ", ")
print("Products:", products)
let targets = manifest.targets.map({ $0.name }).joined(separator: ", ")
print("Targets:", targets)

// Package
let executables = loadedPackage.targets.filter({ $0.type == .executable }).map({ $0.name })
print("Executable targets:", executables)

// PackageGraph
let numberOfFiles = graph.reachableTargets.reduce(0, { $0 + $1.sources.paths.count })
print("Total number of source files (including dependencies):", numberOfFiles)
