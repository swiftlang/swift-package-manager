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

// FIXME: We have no @testable way to import generic structures.
@testable import PackageGraph

extension String: PackageContainerIdentifier { }

private typealias MockPackageConstraint = PackageContainerConstraint<String>

private enum MockLoadingError: Error {
    case unknownModule
}

private struct MockPackageContainer: PackageContainer {
    typealias Identifier = String

    let name: Identifier

    let dependenciesByVersion: [Version: [(container: Identifier, versionRequirement: VersionSetSpecifier)]]

    var identifier: Identifier {
        return name
    }

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

// Some handy ranges.

private let v1: Version = "1.0.0"
private let v2: Version = "2.0.0"
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")
private let v1_to_3Range: VersionSetSpecifier = .range("1.0.0" ..< "3.0.0")
private let v2Range: VersionSetSpecifier = .range("2.0.0" ..< "3.0.0")
private let v2_to_4Range: VersionSetSpecifier = .range("2.0.0" ..< "4.0.0")
private let v1_0Range: VersionSetSpecifier = .range("1.0.0" ..< "1.1.0")
private let v1_1Range: VersionSetSpecifier = .range("1.1.0" ..< "1.2.0")
private let v1_1_0Range: VersionSetSpecifier = .range("1.1.0" ..< "1.1.1")
private let v2_0_0Range: VersionSetSpecifier = .range("2.0.0" ..< "2.0.1")

class DependencyResolverTests: XCTestCase {
    func testBasics() throws {
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
        XCTAssert(v1Range.intersection(.any) == v1Range)
        XCTAssert(VersionSetSpecifier.empty.intersection(.any) == .empty)
        XCTAssert(VersionSetSpecifier.any.intersection(.any) == .any)
    }

    func testContainerConstraintSet() {
        typealias ConstraintSet = PackageContainerConstraintSet<MockPackageContainer>

        var set = ConstraintSet()
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }, [])

        // Check basics.
        XCTAssertTrue(set.merge(MockPackageConstraint(container: "A", versionRequirement: v1Range)))
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }, ["A"])
        XCTAssertEqual(set["A"], v1Range)
        XCTAssertTrue(set.merge(MockPackageConstraint(container: "B", versionRequirement: v2Range)))
        XCTAssertEqual(set.containerIdentifiers.sorted(), ["A", "B"])

        // Check merging a constraint which makes the set unsatisfiable.
        XCTAssertFalse(set.merge(MockPackageConstraint(container: "A", versionRequirement: v2Range)))
        XCTAssertEqual(set["A"], VersionSetSpecifier.empty)

        // Check merging other sets.
        var set2 = ConstraintSet()
        _ = set2.merge(MockPackageConstraint(container: "C", versionRequirement: v1Range))
        XCTAssertTrue(set.merge(set2))
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }.sorted(), ["A", "B", "C"])
        var set3 = ConstraintSet()
        _ = set3.merge(MockPackageConstraint(container: "C", versionRequirement: v2Range))
        _ = set3.merge(MockPackageConstraint(container: "D", versionRequirement: v1Range))
        _ = set3.merge(MockPackageConstraint(container: "E", versionRequirement: v1Range))
        XCTAssertFalse(set.merge(set3)) // "C" requirement is unsatisfiable
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }.sorted(), ["A", "B", "C", "D", "E"])
    }

    func testVersionAssignment() {
        let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                v1: [(container: "B", versionRequirement: v1Range)],
                v2: [(container: "C", versionRequirement: v1_0Range)],
            ])
        let b = MockPackageContainer(name: "B", dependenciesByVersion: [
                v1: [(container: "C", versionRequirement: v1Range)]])
        let c = MockPackageContainer(name: "C", dependenciesByVersion: [
                v1: []])

        var assignment = VersionAssignmentSet<MockPackageContainer>()
        XCTAssertEqual(assignment.constraints, [:])
        XCTAssert(assignment.isValid(binding: .version(v2), for: b))
        // An empty assignment is valid.
        XCTAssert(assignment.checkIfValidAndComplete())

        // Add an assignment and check the constraints.
        assignment[a] = .version(v1)
        XCTAssertEqual(assignment.constraints, ["B": v1Range])
        XCTAssert(assignment.isValid(binding: .version(v1), for: b))
        XCTAssert(!assignment.isValid(binding: .version(v2), for: b))
        // This is invalid (no 'B' assignment).
        XCTAssert(!assignment.checkIfValidAndComplete())

        // Check another assignment.
        assignment[b] = .version(v1)
        XCTAssertEqual(assignment.constraints, ["B": v1Range, "C": v1Range])
        XCTAssert(!assignment.checkIfValidAndComplete())

        // Check excluding 'A'.
        assignment[a] = .excluded
        XCTAssertEqual(assignment.constraints, ["C": v1Range])
        XCTAssert(!assignment.checkIfValidAndComplete())

        // Check completing the assignment.
        assignment[c] = .version(v1)
        XCTAssert(assignment.checkIfValidAndComplete())

        // Check bringing back 'A' at a different version, which has only a more
        // restrictive 'C' dependency.
        assignment[a] = .version(v2)
        XCTAssertEqual(assignment.constraints, ["C": v1_0Range])
        XCTAssert(assignment.checkIfValidAndComplete())
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
        ("testContainerConstraintSet", testContainerConstraintSet),
        ("testVersionAssignment", testVersionAssignment),
    ]
}

private func ==(_ lhs: [String: VersionSetSpecifier], _ rhs: [String: VersionSetSpecifier]) -> Bool {
    if lhs.count != rhs.count {
        return false
    }
    for (key, lhsSet) in lhs {
        guard let rhsSet = rhs[key] else { return false }
        if lhsSet != rhsSet {
            return false
        }
    }
    return true
}

private func XCTAssertEqual<C: PackageContainer>(
    _ constraints: PackageContainerConstraintSet<C>,
    _ expected: [String: VersionSetSpecifier],
    file: StaticString = #file, line: UInt = #line)
where C.Identifier == String
{
    var actual = [String: VersionSetSpecifier]()
    for identifier in constraints.containerIdentifiers {
        actual[identifier] = constraints[identifier]!
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}
