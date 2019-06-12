import Workspace

/// The path of the package.
let package = localFileSystem.currentWorkingDirectory!

/// Determine the directory that contains SwiftPM's PackageDescription libs.
let libDir = AbsolutePath(#file).appending(RelativePath("../../../.build/.bootstrap/lib/swift/pm"))

// Load package's manifest.
let loader = ManifestLoader(manifestResources: UserManifestResources(libDir: libDir))
let manifest = try loader.load(packagePath: package)

print("Name in the manifest:", manifest.name)

/// Create a workspace for the package.
let workspace = Workspace.create(forRootPackage: package, libDir: libDir)

/// Load it's package graph.
let diagnostics = DiagnosticsEngine()
let packageGraph = workspace.loadPackageGraph(root: package, diagnostics: diagnostics)

let numberOfFiles = packageGraph.allTargets.reduce(0, { $0 + $1.sources.paths.count })
print("Number of source files:", numberOfFiles)

let rootPackageTargets = packageGraph.rootPackages.flatMap({ $0.targets }).map({ $0.name }).joined(separator: ", ")
print("Targets:", rootPackageTargets)

let products = packageGraph.allProducts.map({ $0.name }).joined(separator: ", ")
print("Products:", products)
