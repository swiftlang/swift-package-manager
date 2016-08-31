/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel
import PackageLoading

// FIXME: This doesn't belong here.
import func POSIX.exit

enum PackageGraphError: Swift.Error {
    /// Indicates two modules with the same name.
    case duplicateModule(String)

    /// Indicates a non-root package with no modules.
    case noModules(Package)
}

extension PackageGraphError: FixableError {
    var error: String {
        switch self {
        case .duplicateModule(let name):
            return "multiple modules with the name \(name) found"
        case .noModules(let package):
            return "the package \(package) contains no modules"
        }
    }

    var fix: String? {
        switch self {
        case .duplicateModule(_):
            return "modules should have a unique name across dependencies"
        case .noModules(_):
            return "create at least one module"
        }
    }
}

/// A helper class for loading a package graph.
public struct PackageGraphLoader {
    /// Create a package loader.
    public init() { }

    /// Load the package graph for the given package path.
    public func load(rootManifest: Manifest, externalManifests: [Manifest], fileSystem: FileSystem = localFileSystem) throws -> PackageGraph {
        let allManifests = externalManifests + [rootManifest]

        // Create the packages and convert to modules.
        var packages: [Package] = []
        var map: [Package: [Module]] = [:]
        for (i, manifest) in allManifests.enumerated() {
            let isRootPackage = (i + 1) == allManifests.count

            // Derive the path to the package.
            //
            // FIXME: Lift this out of the manifest.
            let packagePath = manifest.path.parentDirectory

            // Create a package from the manifest and sources.
            //
            // FIXME: We should always load the tests, but just change which
            // tests we build based on higher-level logic. This would make it
            // easier to allow testing of external package tests.
            let builder = PackageBuilder(manifest: manifest, path: packagePath, fileSystem: fileSystem)
            let package = try builder.construct(includingTestModules: isRootPackage)
            packages.append(package)
            
            map[package] = package.modules + package.testModules

            // Diagnose empty non-root packages, which are something we allow as a special case.
            if package.modules.isEmpty {
                if isRootPackage {
                    // Ignore and print warning if root package doesn't contain any sources.
                    print("warning: root package '\(package)' does not contain any sources")
                    
                    // Exit now if there are no more packages.
                    //
                    // FIXME: This does not belong here.
                    if allManifests.count == 1 { exit(0) }
                } else {
                    throw PackageGraphError.noModules(package)
                }
            }
        }

        // Load all of the package dependencies.
        //
        // FIXME: Do this concurrently with creating the packages so we can create immutable ones.
        for package in packages {
            // FIXME: This is inefficient.
            package.dependencies = package.manifest.package.dependencies.map{ dep in packages.pick{ dep.url == $0.url }! }
        }
    
        // Connect up cross-package module dependencies.
        fillModuleGraph(packages)
    
        let rootPackage = packages.last!
        let externalPackages = packages.dropLast(1)

        let modules = try recursiveDependencies(packages.flatMap{ map[$0] ?? [] })
        let externalModules = try recursiveDependencies(externalPackages.flatMap{ map[$0] ?? [] })

        return PackageGraph(rootPackage: rootPackage, modules: modules, externalModules: Set(externalModules))
    }
}

/// Add inter-package dependencies.
///
/// This function will add cross-package dependencies between a module and all
/// of the modules produced by any package in the transitive closure of its
/// containing package's dependencies.
private func fillModuleGraph(_ packages: [Package]) {
    for package in packages {
        let packageModules = package.modules + package.testModules
        let dependencies = try! topologicalSort(package.dependencies, successors: { $0.dependencies })
        for dep in dependencies {
            let depModules = dep.modules.filter {
                guard !$0.isTest else { return false }

                switch $0 {
                case let module as SwiftModule where module.type == .library:
                    return true
                case let module as ClangModule where module.type == .library:
                    return true
                case is CModule:
                    return true
                default:
                    return false
                }
            }
            for module in packageModules {
                // FIXME: This is inefficient.
                module.dependencies.insert(contentsOf: depModules, at: 0)
            }
        }
    }
}

private func recursiveDependencies(_ modules: [Module]) throws -> [Module] {
    // FIXME: Refactor this to a common algorithm.
    var stack = modules
    var set = Set<Module>()
    var rv = [Module]()

    while stack.count > 0 {
        let top = stack.removeFirst()
        if !set.contains(top) {
            rv.append(top)
            set.insert(top)
            stack += top.dependencies
        } else {
            // See if the module in the set is actually the same.
            guard let index = set.index(of: top),
                  top.sources.root != set[index].sources.root else {
                continue;
            }

            throw PackageGraphError.duplicateModule(top.name)
        }
    }

    return rv
}
