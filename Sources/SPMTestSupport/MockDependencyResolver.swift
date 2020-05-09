/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/
import XCTest
import Dispatch

import TSCBasic
import PackageModel
import PackageGraph
import SourceControl

import struct TSCUtility.Version

public typealias MockPackageConstraint = PackageContainerConstraint

extension MockPackageConstraint {
    public init(container identifier: String, requirement: PackageRequirement, products: ProductFilter) {
        let ref = PackageReference(identity: identifier.lowercased(), path: "")
        self.init(container: ref, requirement: requirement, products: products)
    }

    public init(container identifier: String, versionRequirement: VersionSetSpecifier, products: ProductFilter) {
        let ref = PackageReference(identity: identifier.lowercased(), path: "")
        self.init(container: ref, versionRequirement: versionRequirement, products: products)
    }
}

extension VersionSetSpecifier {
    init(_ json: JSON) {
        switch json {
        case let .string(str):
            switch str {
            case "any": self = .any
            case "empty": self = .empty
            default: fatalError()
            }
        case let .array(arr):
            switch arr.count {
            case 1:
                guard case let .string(str) = arr[0] else { fatalError() }
                self = .exact(Version(string: str)!)
            case 2:
                let versions = arr.map({ json -> Version in
                    guard case let .string(str) = json else { fatalError() }
                    return Version(string: str)!
                })
                self = .range(versions[0] ..< versions[1])
            default: fatalError()
            }
        default: fatalError()
        }
    }
}

extension PackageContainerConstraint {
    public init(json: JSON) {
        guard case let .dictionary(dict) = json else { fatalError() }
        guard case let .string(identifier)? = dict["identifier"] else { fatalError() }
        guard let requirement = dict["requirement"] else { fatalError() }
        let products: ProductFilter = try! JSON(dict).get("products")
        let id = PackageReference(identity: identifier.lowercased(), path: "", kind: .remote)
        self.init(container: id, versionRequirement: VersionSetSpecifier(requirement), products: products)
    }
}

extension PackageContainerProvider {
    public func getContainer(
        for identifier: PackageReference,
        completion: @escaping (Result<PackageContainer, Error>) -> Void
    ) {
        getContainer(for: identifier, skipUpdate: false, completion: completion)
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
        return dependencies[revision]!.map({ value in
            let (name, requirement) = value
            return MockPackageConstraint(container: name, requirement: requirement, products: productFilter)
        })
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
            dependencies[version.description] = deps.map({
                let ref = PackageReference(identity: $0.container.lowercased(), path: "/\($0.container)")
                return (ref, .versionSet($0.versionRequirement))
            })
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

    public var _isRemoteContainer: Bool? {
        return true
    }
}

public class MockPackageContainer2: MockPackageContainer {
    public override func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return name.with(newName: name.identity + "-name")
    }
}

extension MockPackageContainer {
    public convenience init(json: JSON) {
        guard case let .dictionary(dict) = json else { fatalError() }
        guard case let .string(identifier)? = dict["identifier"] else { fatalError() }
        guard case let .dictionary(versions)? = dict["versions"] else { fatalError() }

        var depByVersion: [Version: [(container: String, versionRequirement: VersionSetSpecifier)]] = [:]
        for (version, deps) in versions {
            guard case let .array(depArray) = deps else { fatalError() }
            depByVersion[Version(string: version)!] = depArray
                .map(PackageContainerConstraint.init(json:))
                .map({ constraint in
                    switch constraint.requirement {
                    case .versionSet(let versionSet):
                        return (constraint.identifier.identity, versionSet)
                    case .unversioned:
                        fatalError()
                    case .revision:
                        fatalError()
                    }
                })
        }

        self.init(name: identifier, dependenciesByVersion: depByVersion)
    }
}

public struct MockPackagesProvider: PackageContainerProvider {

    public let containers: [MockPackageContainer]
    public let containersByIdentifier: [PackageReference: MockPackageContainer]

    public init(containers: [MockPackageContainer]) {
        self.containers = containers
        self.containersByIdentifier = Dictionary(uniqueKeysWithValues: containers.map({ ($0.identifier, $0) }))
    }

    public func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Error>
    ) -> Void) {
        DispatchQueue.global().async {
            completion(self.containersByIdentifier[identifier].map{ .success($0) } ??
                .failure(MockLoadingError.unknownModule))
        }
    }
}

public class MockResolverDelegate: DependencyResolverDelegate {
    public typealias Identifier = MockPackageContainer.Identifier

    public init() {}
}

extension DependencyResolver {
    /// Helper method which returns all the version binding out of resolver and assert failure for non version bindings.
    public func resolveToVersion(
        constraints: [MockPackageConstraint],
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> [(container: String, version: Version)] {
        fatalError()
    }
}

public struct MockGraph {

    public let name: String
    public let constraints: [MockPackageConstraint]
    public let containers: [MockPackageContainer]
    public let result: [String: Version]

    public init(_ json: JSON) {
        guard case let .dictionary(dict) = json else { fatalError() }
        guard case let .string(name)? = dict["name"] else { fatalError() }
        guard case let .array(constraints)? = dict["constraints"] else { fatalError() }
        guard case let .array(containers)? = dict["containers"] else { fatalError() }
        guard case let .dictionary(result)? = dict["result"] else { fatalError() }

        self.result = Dictionary(uniqueKeysWithValues: result.map({ value in
            let (container, version) = value
            guard case let .string(str) = version else { fatalError() }
            return (container.lowercased(), Version(string: str)!)
        }))
        self.name = name
        self.constraints = constraints.map(PackageContainerConstraint.init(json:))
        self.containers = containers.map(MockPackageContainer.init(json:))
    }

    public func checkResult(
        _ output: [(container: String, version: Version)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        var result = self.result
        for item in output {
            XCTAssertEqual(result[item.container], item.version, file: file, line: line)
            result[item.container] = nil
        }
        if !result.isEmpty {
            XCTFail("Unchecked containers: \(result)", file: file, line: line)
        }
    }
}

import struct PackageModel.PackageReference

public func XCTAssertEqual<T: CustomStringConvertible>(
    _ assignment: [(container: T, version: Version)],
    _ expected: [T: Version],
    file: StaticString = #file, line: UInt = #line)
    where T: Hashable
{
    var actual = [T: Version]()
    for (identifier, binding) in assignment {
        actual[identifier] = binding
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}
