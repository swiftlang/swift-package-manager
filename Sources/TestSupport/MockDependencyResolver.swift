/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/
import XCTest
import Dispatch

import Basic
import PackageGraph
import SourceControl

import struct Utility.Version

public typealias MockDependencyResolver = DependencyResolver<MockPackagesProvider, MockResolverDelegate>

extension String: PackageContainerIdentifier { }

public typealias MockPackageConstraint = PackageContainerConstraint<String>

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

extension PackageContainerConstraint where T == String {
    public init(json: JSON) {
        guard case let .dictionary(dict) = json else { fatalError() }
        guard case let .string(identifier)? = dict["identifier"] else { fatalError() }
        guard let requirement = dict["requirement"] else { fatalError() }
        self.init(container: identifier, versionRequirement: VersionSetSpecifier(requirement))
    }
}

extension PackageContainerProvider {
    public func getContainer(
        for identifier: Container.Identifier,
        completion: @escaping (Result<Container, AnyError>) -> Void
    ) {
        getContainer(for: identifier, skipUpdate: false, completion: completion)
    }
}

public enum MockLoadingError: Error {
    case unknownModule
}

public final class MockPackageContainer: PackageContainer {
    public typealias Identifier = String

    public typealias Dependency = (container: Identifier, requirement: MockPackageConstraint.Requirement)

    let name: Identifier

    let dependencies: [String: [Dependency]]

    /// Contains the versions for which the dependencies were requested by resolver using getDependencies().
    public var requestedVersions: Set<Version> = []

    public var identifier: Identifier {
        return name
    }

    public let _versions: [Version]
    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(_versions.filter(isIncluded))
    }

    public func getDependencies(at version: Version) -> [MockPackageConstraint] {
        requestedVersions.insert(version)
        return getDependencies(at: version.description)
    }

    public func getDependencies(at revision: String) -> [MockPackageConstraint] {
        return dependencies[revision]!.map({ value in
            let (name, requirement) = value
            return MockPackageConstraint(container: name, requirement: requirement)
        })
    }

    public convenience init(
        name: Identifier,
        dependenciesByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]]
    ) {
        var dependencies: [String: [Dependency]] = [:]
        for (version, deps) in dependenciesByVersion {
            dependencies[version.description] = deps.map({
                ($0.container, .versionSet($0.versionRequirement))
            })
        }
        self.init(name: name, dependencies: dependencies)
    }

    public init(
        name: Identifier,
        dependencies: [String: [Dependency]] = [:]
    ) {
        self.name = name
        let versions = dependencies.keys.flatMap(Version.init(string:))
        self._versions = versions.sorted().reversed()
        self.dependencies = dependencies
    }
}

extension MockPackageContainer {
    public convenience init(json: JSON) {
        guard case let .dictionary(dict) = json else { fatalError() }
        guard case let .string(identifier)? = dict["identifier"] else { fatalError() }
        guard case let .dictionary(versions)? = dict["versions"] else { fatalError() }

        var depByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]] = [:]
        for (version, deps) in versions {
            guard case let .array(depArray) = deps else { fatalError() }
            depByVersion[Version(string: version)!] = depArray
                .map(PackageContainerConstraint.init(json:))
                .map({ constraint in
                    switch constraint.requirement {
                    case .versionSet(let versionSet):
                        return (constraint.identifier, versionSet)
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
    public typealias Container = MockPackageContainer

    public let containers: [Container]
    public let containersByIdentifier: [Container.Identifier: Container]

    public init(containers: [MockPackageContainer]) {
        self.containers = containers
        self.containersByIdentifier = Dictionary(items: containers.map({ ($0.identifier, $0) }))
    }

    public func getContainer(
        for identifier: Container.Identifier,
        skipUpdate: Bool,
        completion: @escaping (Result<Container, AnyError>
    ) -> Void) {
        DispatchQueue.global().async {
            completion(self.containersByIdentifier[identifier].map(Result.init) ??
                Result(MockLoadingError.unknownModule))
        }
    }
}

public class MockResolverDelegate: DependencyResolverDelegate {
    public typealias Identifier = MockPackageContainer.Identifier

    public init() {}
}

extension DependencyResolver where P == MockPackagesProvider, D == MockResolverDelegate {
    /// Helper method which returns all the version binding out of resolver and assert failure for non version bindings.
    public func resolveToVersion(
        constraints: [MockPackageConstraint],
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> [(container: String, version: Version)] {
        return try resolve(constraints: constraints).flatMap({
            guard case .version(let version) = $0.binding else {
                XCTFail("Unexpected non version binding \($0.binding)", file: file, line: line)
                return nil
            }
            return ($0.container, version)
        })
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

        self.result = Dictionary(items: result.map({ value in
            let (container, version) = value
            guard case let .string(str) = version else { fatalError() }
            return (container, Version(string: str)!)
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

public func XCTAssertEqual<I: PackageContainerIdentifier>(
    _ assignment: [(container: I, version: Version)],
    _ expected: [I: Version],
    file: StaticString = #file, line: UInt = #line) {
    var actual = [I: Version]()
    for (identifier, binding) in assignment {
        actual[identifier] = binding
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}
