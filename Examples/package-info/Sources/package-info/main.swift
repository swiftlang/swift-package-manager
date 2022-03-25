import TSCBasic
import SPMClientUtils

// PREREQUISITES
// ============

// We need a package to work with.
// This computes the path of this package root based on the file location
let packagePath = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory

// LOADING
// =======

// There are several levels of information available.
// Each takes longer to load than the level above it, but provides more detail.

let observer = DiagnosticObserver({ (scope: String, diagnostic: String) in
  print("\(scope): \(diagnostic)")
})

let workspace = try Workspace(forRootPackage: packagePath)

let manifest = try tsc_await { workspace.loadRootManifest(at: packagePath, diagnosticObserver: observer, completion: $0) }

let package = try tsc_await { workspace.loadRootPackage(at: packagePath, diagnosticObserver: observer, completion: $0) }

let graph = try workspace.loadPackageGraph(rootPath: packagePath, diagnosticObserver: observer)

// EXAMPLES
// ========

// Manifest
let products = manifest.products.map({ $0.name }).joined(separator: ", ")
print("Products:", products)
let targets = manifest.targets.map({ $0.name }).joined(separator: ", ")
print("Targets:", targets)

// Package
let executables = package.targets.filter({ $0.type == .executable }).map({ $0.name })
print("Executable targets:", executables)

// PackageGraph
let numberOfFiles = graph.reachableTargets.reduce(0, { $0 + $1.sources.paths.count })
print("Total number of source files (including dependencies):", numberOfFiles)
