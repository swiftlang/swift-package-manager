/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import PackageGraph

import struct Utility.Version

import TestSupport

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
        return dependenciesByVersion.keys.sorted()
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

private typealias MockDependencyResolver = DependencyResolver<MockPackagesProvider, MockResolverDelegate>

// Some handy ranges.
//
// The convention is that the name matches how specific the version is, so "v1"
// means "any 1.?.?", and "v1_1" means "any 1.1.?".

private let v1: Version = "1.0.0"
private let v1_1: Version = "1.1.0"
private let v2: Version = "2.0.0"
private let v0_0_0Range: VersionSetSpecifier = .range("0.0.0" ..< "0.0.1")
private let v1Range: VersionSetSpecifier = .range("1.0.0" ..< "2.0.0")
private let v1to3Range: VersionSetSpecifier = .range("1.0.0" ..< "3.0.0")
private let v2Range: VersionSetSpecifier = .range("2.0.0" ..< "3.0.0")
private let v1_to_3Range: VersionSetSpecifier = .range("1.0.0" ..< "3.0.0")
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
                        v1: [], v2: []])])

        let delegate = MockResolverDelegate()
        let resolver = DependencyResolver(provider, delegate)
        let packages = try resolver.resolve(constraints: [
                MockPackageConstraint(container: "A", versionRequirement: v1Range)])
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
        set = set.merging(MockPackageConstraint(container: "A", versionRequirement: v1Range))!
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }, ["A"])
        XCTAssertEqual(set["A"], v1Range)
        set = set.merging(MockPackageConstraint(container: "B", versionRequirement: v2Range))!
        XCTAssertEqual(set.containerIdentifiers.sorted(), ["A", "B"])

        // Check merging a constraint which makes the set unsatisfiable.
        XCTAssert(set.merging(MockPackageConstraint(container: "A", versionRequirement: v2Range)) == nil)

        // Check merging other sets.
        var set2 = ConstraintSet()
        set2 = set2.merging(MockPackageConstraint(container: "C", versionRequirement: v1Range))!
        set = set.merging(set2)!
        XCTAssertEqual(set.containerIdentifiers.map{ $0 }.sorted(), ["A", "B", "C"])
        var set3 = ConstraintSet()
        set3 = set3.merging(MockPackageConstraint(container: "C", versionRequirement: v2Range))!
        set3 = set3.merging(MockPackageConstraint(container: "D", versionRequirement: v1Range))!
        set3 = set3.merging(MockPackageConstraint(container: "E", versionRequirement: v1Range))!
        XCTAssert(set.merging(set3) == nil) // "C" requirement is unsatisfiable
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

        // Check assignment merging.
        let d = MockPackageContainer(name: "D", dependenciesByVersion: [
                v1: [(container: "E", versionRequirement: v1Range)],
                v2: []])
        var assignment2 = VersionAssignmentSet<MockPackageContainer>()
        assignment2[d] = .version(v1)
        if let mergedAssignment = assignment.merging(assignment2) {
            assignment = mergedAssignment
        } else {
            return XCTFail("unexpected failure merging assignment")
        }
        XCTAssertEqual(assignment.constraints, ["C": v1_0Range, "E": v1Range])

        // Check merger of an assignment with incompatible constraints.
        let d2 = MockPackageContainer(name: "D2", dependenciesByVersion: [
                v1: [(container: "E", versionRequirement: v2Range)]])
        var assignment3 = VersionAssignmentSet<MockPackageContainer>()
        assignment3[d2] = .version(v1)
        XCTAssertEqual(assignment.merging(assignment3), nil)

        // Check merger of an incompatible assignment.
        var assignment4 = VersionAssignmentSet<MockPackageContainer>()
        assignment4[d] = .version(v2)
        XCTAssertEqual(assignment.merging(assignment4), nil)
    }

    /// Check the basic situations for resolving a subtree.
    func testResolveSubtree() throws {
        typealias ConstraintSet = MockDependencyResolver.ConstraintSet

        // Check respect for the input constraints on version selection.
        do {
            let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                    v1: [(container: "B", versionRequirement: v1Range)],
                    v2: [(container: "B", versionRequirement: v1Range)]])
            let b = MockPackageContainer(name: "B", dependenciesByVersion: [
                    v1: [], v2: []])
            let provider = MockPackagesProvider(containers: [a, b])
            let delegate = MockResolverDelegate()
            let resolver = MockDependencyResolver(provider, delegate)

            // Check the unconstrained solution.
            XCTAssertEqual(
                try resolver.resolveSubtree(a, subjectTo: ConstraintSet(), excluding: [:]),
                ["A": v2, "B": v1])

            // Check when constraints prevents a specific version.
            XCTAssertEqual(
                try resolver.resolveSubtree(a, subjectTo: ["A": v1Range]),
                ["A": v1, "B": v1])

            // Check when constraints prevent resolution.
            XCTAssertEqual(
                try resolver.resolveSubtree(a, subjectTo: ["A": v0_0_0Range]),
                nil)
            XCTAssertEqual(
                try resolver.resolveSubtree(a, subjectTo: ["B": v0_0_0Range]),
                nil)
        }

        // Check respect for the constraints induced by the initial package.
        do {
            let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                    v1: [],
                    v2: [(container: "B", versionRequirement: v1Range)]])
            let provider = MockPackagesProvider(containers: [a])
            let delegate = MockResolverDelegate()
            let resolver = MockDependencyResolver(provider, delegate)

            // Check that this throws, because we try to fetch "B".
            XCTAssertThrows(MockLoadingError.unknownModule) {
                _ = try resolver.resolveSubtree(a)
            }

            // Check that this works, because we skip ever trying the version
            // referencing "C" because the it is unsatisfiable.
            XCTAssertEqual(
                try resolver.resolveSubtree(a, subjectTo: ["B": v0_0_0Range]),
                ["A": v1])
        }

        // Check when a subtree is unsolvable.
        do {
            let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                    v1: [],
                    v2: [(container: "B", versionRequirement: v1Range)]])
            let b = MockPackageContainer(name: "B", dependenciesByVersion: [
                    v1: [(container: "C", versionRequirement: v2Range)]])
            let provider = MockPackagesProvider(containers: [a, b])
            let delegate = MockResolverDelegate()
            let resolver = MockDependencyResolver(provider, delegate)

            // FIXME: This should return a `["A": v1]` assignment.
            XCTAssertThrows(DependencyResolverError.unimplemented) {
                _ = try resolver.resolveSubtree(a, subjectTo: ["C": v0_0_0Range])
            }
        }

        // Check when a subtree can't be merged.
        do {
            let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                    v1: [],
                    v2: [
                        (container: "B", versionRequirement: v1Range),
                        (container: "C", versionRequirement: v1Range)]])
            // B will pick `"D" == v1_1`, due to the more limited range.
            let b = MockPackageContainer(name: "B", dependenciesByVersion: [
                    v1: [(container: "D", versionRequirement: v1Range)]])
            // C will pick `"D" == v1_0`, due to the more limited range (but not
            // due to the top-down constraints, which is the case covered
            // previously).
            let c = MockPackageContainer(name: "C", dependenciesByVersion: [
                    v1: [(container: "D", versionRequirement: v1_0Range)]])
            let d = MockPackageContainer(name: "D", dependenciesByVersion: [
                    v1: [], v1_1: []])
            let provider = MockPackagesProvider(containers: [a, b, c, d])
            let delegate = MockResolverDelegate()
            let resolver = MockDependencyResolver(provider, delegate)

            // FIXME: This should return a `["A": v1]` assignment.
            XCTAssertThrows(DependencyResolverError.unimplemented) {
                _ = try resolver.resolveSubtree(a)
            }
        }
    }

    /// Check the basic situations for resolve().
    ///
    /// This is primarily tested via `resolveSubtree`.
    func testResolve() throws {
        typealias ConstraintSet = MockDependencyResolver.ConstraintSet

        // Check respect for the input constraints on version selection.
        do {
            let a = MockPackageContainer(name: "A", dependenciesByVersion: [
                    v1: [], v2: []])
            let provider = MockPackagesProvider(containers: [a])
            let delegate = MockResolverDelegate()
            let resolver = MockDependencyResolver(provider, delegate)

            // Check the constraints are respected.
            XCTAssertEqual(
                try resolver.resolve(constraints: [
                        MockPackageConstraint(container: "A", versionRequirement: v1to3Range),
                        MockPackageConstraint(container: "A", versionRequirement: v1Range)]),
                ["A": v1])

            // Check the constraints are respected if unsatisfiable.
            XCTAssertThrows(DependencyResolverError.unsatisfiable) {
                _ = try resolver.resolve(constraints: [
                        MockPackageConstraint(container: "A", versionRequirement: v1Range),
                        MockPackageConstraint(container: "A", versionRequirement: v2Range)])
            }
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
        ("testContainerConstraintSet", testContainerConstraintSet),
        ("testVersionAssignment", testVersionAssignment),
        ("testResolveSubtree", testResolveSubtree),
        ("testResolve", testResolve),
    ]
}

private extension DependencyResolver {
    func resolveSubtree(
        _ container: Container,
        subjectTo allConstraints: [Identifier: VersionSetSpecifier] = [:],
        excluding exclusions: [Identifier: Set<Version>] = [:]
    ) throws -> AssignmentSet? {
        return try resolveSubtree(container, subjectTo: ConstraintSet(allConstraints), excluding: exclusions)
    }
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
        actual[identifier] = constraints[identifier]
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}

private func XCTAssertEqual<C: PackageContainer>(
    _ assignment: VersionAssignmentSet<C>?,
    _ expected: [String: Version]?,
    file: StaticString = #file, line: UInt = #line)
where C.Identifier == String
{
    if let assignment = assignment {
        guard let expected = expected else {
            return XCTFail("unexpected satisfying assignment (expected failure): \(assignment)", file: file, line: line)
        }
        var actual = [String: Version]()
        for (container, binding) in assignment {
            guard case .version(let version) = binding else {
                return XCTFail("unexpected binding in \(assignment)", file: file, line: line)
            }
            actual[container.identifier] = version
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    } else {
        if let expected = expected {
            return XCTFail("unexpected missing assignment, expected: \(expected)", file: file, line: line)
        }
    }
}

func XCTAssertEqual<I: PackageContainerIdentifier>(
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
