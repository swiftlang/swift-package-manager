/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import PackageGraph

import struct PackageDescription.Version
extension Version: Hashable {
    public var hashValue: Int {
        let mul: UInt64 = 0x9ddfea08eb382d69
        var result: UInt64 = 0
        result = (result &* mul) ^ UInt64(major.hashValue)
        result = (result &* mul) ^ UInt64(minor.hashValue)
        result = (result &* mul) ^ UInt64(patch.hashValue)
        result = prereleaseIdentifiers.reduce(result, { ($0 &* mul) ^ UInt64($1.hashValue) })
        if let build = buildMetadataIdentifier {
            result = (result &* mul) ^ UInt64(build.hashValue)
        }
        return Int(result)
    }
}

extension String: PackageContainerIdentifier { }

private typealias MockPackageConstraint = PackageContainerConstraint<String>

private enum MockLoadingError: Error {
    case unknownModule
}

private struct MockPackageContainer: PackageContainer {
    typealias Identifier = String

    let name: Identifier

    let dependenciesByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]]

    var versions: [Version] {
        return dependenciesByVersion.keys.sorted().reversed()
    }

    func getDependencies(at version: Version) -> [MockPackageConstraint] {
        return dependenciesByVersion[version]!.map{ (name, versions) in
            return MockPackageConstraint(container: name, versionRequirement: versions)
        }
    }
}

private struct MockPackagesProvider: PackageContainerProvider {
    typealias Container = MockPackageContainer

    let containers: [MockPackageContainer]

    func getContainer(for identifier: Container.Identifier) throws -> Container {
        for container in containers {
            if container.name == identifier {
                return container
            }
        }
        throw MockLoadingError.unknownModule
    }
}

private class MockResolverDelegate: DependencyResolverDelegate {
    typealias Identifier = MockPackageContainer.Identifier

    var messages = [String]()

    func added(container identifier: Identifier) {
        messages.append("added container: \(identifier)")
    }
}

class DependencyResolverTests: XCTestCase {
    func testBasics() throws {
        let v1: Version = "1.0.0"
        let v2: Version = "2.0.0"
        let v1Range: VersionSetSpecifier = .range(v1..<v2)

        // Check that a trivial example resolves the closure.
        let provider = MockPackagesProvider(containers: [
                MockPackageContainer(name: "A", dependenciesByVersion: [
                        v1: [(container: "B", versionRequirement: v1Range)]]),
                MockPackageContainer(name: "B", dependenciesByVersion: [
                        v1: [(container: "C", versionRequirement: v1Range)]]),
                MockPackageContainer(name: "C", dependenciesByVersion: [
                        v1: []])])

        let delegate = MockResolverDelegate()
        let resolver = DependencyResolver(
            constraints: [MockPackageConstraint(container: "A", versionRequirement: v1Range)],
            provider: provider,
            delegate: delegate)
        let packages = try resolver.resolve()
        XCTAssertEqual(packages.map{ $0.container }.sorted(), ["A", "B", "C"])
        XCTAssertEqual(delegate.messages, [
                "added container: A",
                "added container: B",
                "added container: C"])
    }

    func testVersionSetSpecifier() {
        let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")
        let v1_to_3Range: VersionSetSpecifier = .range("1.0.0" ..< "3.0.0")
        let v2Range: VersionSetSpecifier = .range("2.0.0" ..< "3.0.0")
        let v2_to_4Range: VersionSetSpecifier = .range("2.0.0" ..< "4.0.0")
        let v1_1Range: VersionSetSpecifier = .range("1.1.0" ..< "1.2.0")
        let v1_1_0Range: VersionSetSpecifier = .range("1.1.0" ..< "1.1.1")
        let v2_0_0Range: VersionSetSpecifier = .range("2.0.0" ..< "2.0.1")

        // Check `contains`.
        XCTAssert(v1Range.contains("1.1.0"))
        XCTAssert(!v1Range.contains("2.0.0"))

        // Check `intersection`.
        XCTAssert(v1Range.intersection(v1_1Range) == v1_1Range)
        XCTAssert(v1Range.intersection(v1_1_0Range) == v1_1_0Range)
        XCTAssert(v1Range.intersection(v2Range) == .empty)
        XCTAssert(v1Range.intersection(v2_0_0Range) == .empty)
        XCTAssert(v1Range.intersection(v1_1Range) == v1_1Range)
        XCTAssert(v1_to_3Range.intersection(v2_to_4Range) == .range("2.0.0" ..< "3.0.0"))
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
    ]
}
