/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/
import XCTest

import Basic
import PackageGraph

import struct Utility.Version

public typealias MockDependencyResolver = DependencyResolver<MockPackagesProvider, MockResolverDelegate>

extension String: PackageContainerIdentifier { }

public typealias MockPackageConstraint = PackageContainerConstraint<String>

public enum MockLoadingError: Error {
    case unknownModule
}

public struct MockPackageContainer: PackageContainer {
    public typealias Identifier = String

    let name: Identifier

    let dependenciesByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]]

    public var identifier: Identifier {
        return name
    }

    public var versions: [Version] {
        return dependenciesByVersion.keys.sorted()
    }

    public func getDependencies(at version: Version) -> [MockPackageConstraint] {
        return dependenciesByVersion[version]!.map{ (name, versions) in
            return MockPackageConstraint(container: name, versionRequirement: versions)
        }
    }

    public init(name: Identifier, dependenciesByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]]) {
        self.name = name
        self.dependenciesByVersion = dependenciesByVersion
    }
}

public struct MockPackagesProvider: PackageContainerProvider {
    public typealias Container = MockPackageContainer

    public let containers: [Container]
    public let containersByIdentifier: [Container.Identifier: Container]

    public init(containers: [MockPackageContainer]) {
        self.containers = containers
        self.containersByIdentifier = Dictionary(items: containers.map{ ($0.identifier, $0) })
    }

    public func getContainer(for identifier: Container.Identifier) throws -> Container {
        if let container = containersByIdentifier[identifier] {
            return container
        }
        throw MockLoadingError.unknownModule
    }
}

public class MockResolverDelegate: DependencyResolverDelegate {
    public typealias Identifier = MockPackageContainer.Identifier

    public var messages = [String]()

    public func added(container identifier: Identifier) {
        messages.append("added container: \(identifier)")
    }

    public init(){}
}

public func XCTAssertEqual<I: PackageContainerIdentifier>(
    _ assignment: [(container: I, version: Version)],
    _ expected: [I: Version],
    file: StaticString = #file, line: UInt = #line)
{
    var actual = [I: Version]()
    for (identifier, binding) in assignment {
        actual[identifier] = binding
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}

