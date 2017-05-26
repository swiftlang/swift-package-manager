/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageGraph
import SourceControl
import struct Utility.Version

private class ResolverToolDelegate: DependencyResolverDelegate, RepositoryManagerDelegate {
    typealias Identifier = RepositoryPackageContainer.Identifier

    func fetchingWillBegin(handle: RepositoryManager.RepositoryHandle) {
        print("note: fetching \(handle.repository.url)")
    }

    func fetchingDidFinish(handle: RepositoryManager.RepositoryHandle, error: Swift.Error?) {
    }
}

extension SwiftPackageTool {
    func executeResolve(_ opts: PackageToolOptions) throws {
        // Load the root manifest.
        let diagnostics = DiagnosticsEngine()
        let manifest = try getActiveWorkspace().loadRootManifests(
            packages: [getPackageRoot()], diagnostics: diagnostics)[0]
        let delegate = ResolverToolDelegate()

        // Create the repository manager.
        let repositoriesPath = buildPath.appending(component: "repositories")
        let repositoryManager = RepositoryManager(
            path: repositoriesPath,
            provider: GitRepositoryProvider(),
            delegate: delegate)

        // Create the container provider interface.
        let provider = RepositoryPackageContainerProvider(
            repositoryManager: repositoryManager, manifestLoader: try getManifestLoader())

        // Create the resolver.
        let resolver = DependencyResolver(provider, delegate)

        // Resolve the dependencies using the manifest constraints.
        let constraints = manifest.package.dependencyConstraints()
        let result = try resolver.resolve(constraints: constraints)

        switch opts.resolveToolMode {
        case .text:
            print("Resolved dependencies for: \(manifest.name)")
            for (container, binding) in result {
                // FIXME: It would be nice to show the reference path, should we get
                // that back or do we need to re-derive it?

                // FIXME: It would be nice to show information on the resulting
                // constraints, e.g., how much latitude do we have on particular
                // dependencies.
                print("  \(container.url): \(binding.description)")
            }
        case .json:
            let json = JSON.dictionary([
                "name": .string(manifest.name),
                "constraints": .array(constraints.map({ $0.toJSON() })),
                "containers": .array(resolver.containers.values.map({ $0.toJSON() })),
                "result": .dictionary(Dictionary(items: result.map({ ($0.0.url, JSON.string($0.1.description)) }))),
            ])
            print(json.toString())
        }
    }
}

// MARK: - JSON Convertible

extension PackageContainerConstraint where T == RepositorySpecifier {
    public func toJSON() -> JSON {
        let requirement: JSON
        switch self.requirement {
        case .versionSet(let versionSet):
            requirement = versionSet.toJSON()
        case .unversioned:
            requirement = .string("unversioned")
        case .revision:
            // FIXME: This needs to be represented properly in a dictionary.
            requirement = .string("revision")
        }
        return .dictionary([
            "identifier": .string(identifier.url),
            "requirement": requirement,
        ])
    }
}

extension VersionSetSpecifier: JSONSerializable {
    public func toJSON() -> JSON {
        switch self {
        case .any:
            return .string("any")
        case .empty:
            return .string("empty")
        case .exact(let version):
            return .array([.string(version.description)])
        case .range(let range):
            var upperBound = range.upperBound
            // Patch the version representation. Ideally we should store in manifest properly.
            if upperBound.minor == .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major+1, 0, 0)
            }
            if upperBound.minor != .max && upperBound.patch == .max {
                upperBound = Version(upperBound.major, upperBound.minor+1, 0)
            }
            return .array([range.lowerBound, upperBound].map({ .string($0.description) }))
        }
    }
}

extension RepositoryPackageContainer: JSONSerializable {
    public func toJSON() -> JSON {
        let depByVersions = versions(filter: { _ in true }).flatMap({ version -> (String, JSON)? in
            // Ignore if we can't load the dependencies.
            guard let deps = try? getDependencies(at: version) else { return nil }
            return (version.description, JSON.array(deps.map({ $0.toJSON() })))
        })

        return .dictionary([
            "identifier": .string(identifier.url),
            "versions": .dictionary(Dictionary(items: depByVersions)),
        ])
    }
}
