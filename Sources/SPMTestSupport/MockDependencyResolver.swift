/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import Dispatch
import XCTest

import PackageGraph
import PackageModel
import SourceControl
import TSCBasic

import struct TSCUtility.Version

public typealias MockPackageConstraint = PackageContainerConstraint

public extension MockPackageConstraint {
    init(container identifier: String, requirement: PackageRequirement, products: ProductFilter) {
        let ref = PackageReference(identity: identifier.lowercased(), path: "")
        self.init(container: ref, requirement: requirement, products: products)
    }

    init(container identifier: String, versionRequirement: VersionSetSpecifier, products: ProductFilter) {
        let ref = PackageReference(identity: identifier.lowercased(), path: "")
        self.init(container: ref, versionRequirement: versionRequirement, products: products)
    }
}

extension VersionSetSpecifier {
    init(_ json: JSON) {
        switch json {
        case .string(let str):
            switch str {
            case "any": self = .any
            case "empty": self = .empty
            default: fatalError()
            }
        case .array(let arr):
            switch arr.count {
            case 1:
                guard case .string(let str) = arr[0] else { fatalError() }
                self = .exact(Version(string: str)!)
            case 2:
                let versions = arr.map { json -> Version in
                    guard case .string(let str) = json else { fatalError() }
                    return Version(string: str)!
                }
                self = .range(versions[0] ..< versions[1])
            default: fatalError()
            }
        default: fatalError()
        }
    }
}

public extension PackageContainerConstraint {
    init(json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let identifier)? = dict["identifier"] else { fatalError() }
        guard let requirement = dict["requirement"] else { fatalError() }
        let products: ProductFilter = try! JSON(dict).get("products")
        let id = PackageReference(identity: identifier.lowercased(), path: "", kind: .remote)
        self.init(container: id, versionRequirement: VersionSetSpecifier(requirement), products: products)
    }
}

public enum MockLoadingError: Error {
    case unknownModule
}

public class MockPackageContainer: PackageContainer {
    public typealias Identifier = PackageReference

    public typealias Dependency = (container: Identifier, requirement: PackageRequirement)

    let name: Identifier

    let dependencies: [String: [Dependency]]

    public var unversionedDeps: [MockPackageConstraint] = []

    /// Contains the versions for which the dependencies were requested by resolver using getDependencies().
    public var requestedVersions: Set<Version> = []

    public var identifier: Identifier {
        return name
    }

    public let _versions: [Version]
    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(_versions.filter(isIncluded))
    }

    public var reversedVersions: [Version] {
        return _versions
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) -> [MockPackageConstraint] {
        requestedVersions.insert(version)
        return getDependencies(at: version.description, productFilter: productFilter)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) -> [MockPackageConstraint] {
        return dependencies[revision]!.map { value in
            let (name, requirement) = value
            return MockPackageConstraint(container: name, requirement: requirement, products: productFilter)
        }
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) -> [MockPackageConstraint] {
        return unversionedDeps
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return name
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        return true
    }

    public convenience init(
        name: String,
        dependenciesByVersion: [Version: [(container: String, versionRequirement: VersionSetSpecifier)]]
    ) {
        var dependencies: [String: [Dependency]] = [:]
        for (version, deps) in dependenciesByVersion {
            dependencies[version.description] = deps.map {
                let ref = PackageReference(identity: $0.container.lowercased(), path: "/\($0.container)")
                return (ref, .versionSet($0.versionRequirement))
            }
        }
        let ref = PackageReference(identity: name.lowercased(), path: "/\(name)")
        self.init(name: ref, dependencies: dependencies)
    }

    public init(
        name: Identifier,
        dependencies: [String: [Dependency]] = [:]
    ) {
        self.name = name
        let versions = dependencies.keys.compactMap(Version.init(string:))
        self._versions = versions.sorted().reversed()
        self.dependencies = dependencies
    }

    public var isRemoteContainer: Bool? {
        return true
    }
}

public extension MockPackageContainer {
    convenience init(json: JSON) {
        guard case .dictionary(let dict) = json else { fatalError() }
        guard case .string(let identifier)? = dict["identifier"] else { fatalError() }
        guard case .dictionary(let versions)? = dict["versions"] else { fatalError() }

        var depByVersion: [Version: [(container: String, versionRequirement: VersionSetSpecifier)]] = [:]
        for (version, deps) in versions {
            guard case .array(let depArray) = deps else { fatalError() }
            depByVersion[Version(string: version)!] = depArray
                .map(PackageContainerConstraint.init(json:))
                .map { constraint in
                    switch constraint.requirement {
                    case .versionSet(let versionSet):
                        return (constraint.identifier.identity, versionSet)
                    case .unversioned:
                        fatalError()
                    case .revision:
                        fatalError()
                    }
                }
        }

        self.init(name: identifier, dependenciesByVersion: depByVersion)
    }
}

public struct MockPackageContainerProvider: PackageContainerProvider {
    public let containers: [MockPackageContainer]
    public let containersByIdentifier: [PackageReference: MockPackageContainer]

    public init(containers: [MockPackageContainer]) {
        self.containers = containers
        self.containersByIdentifier = Dictionary(uniqueKeysWithValues: containers.map { ($0.identifier, $0) })
    }

    public func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Error>
        ) -> Void
    ) {
        DispatchQueue.global().async {
            completion(self.containersByIdentifier[identifier].map { .success($0) } ??
                .failure(MockLoadingError.unknownModule))
        }
    }
}
