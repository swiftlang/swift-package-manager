/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basic
import PackageLoading
import PackageModel
@testable import PackageGraph
import SourceControl

private struct MockPGContainer: PackageContainer {
    typealias Identifier = PackageReference
    var identifier: PackageReference

    var dependencies: [PackageContainerConstraint<PackageReference>]

    init(identifier: PackageReference, dependencies: [Term<PackageReference>] = []) {
        self.identifier = identifier
        self.dependencies = dependencies.map {
            PackageContainerConstraint(container: $0.package, requirement: $0.requirement)
        }
    }

    func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence {
            return [Version(stringLiteral: "1.0.0")].makeIterator()
        }
    }

    func getDependencies(at version: Version) throws -> [PackageContainerConstraint<PackageReference>] {
        return dependencies
    }

    func getDependencies(at revision: String) throws -> [PackageContainerConstraint<PackageReference>] {
        return []
    }

    func getUnversionedDependencies() throws -> [PackageContainerConstraint<PackageReference>] {
        return []
    }

    func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return identifier
    }
}

private class MockPGProvider: PackageContainerProvider {
    typealias Container = MockPGContainer

    var containers: [MockPGContainer.Identifier: MockPGContainer] = [:]

    func getContainer(for identifier: MockPGContainer.Identifier, skipUpdate: Bool, completion: @escaping (Result<MockPGContainer, AnyError>) -> Void) {
        guard let container = containers[identifier] else {
            fatalError("container not found")
        }
        completion(.success(container))
    }

    func _register(package: PackageReference, dependencies: [Term<PackageReference>] = []) {
        containers[package] = MockPGContainer(identifier: package, dependencies: dependencies)
        dependencies.forEach {
            containers[$0.package] = MockPGContainer(identifier: $0.package)
        }
    }
}

struct MockPGDelegate: DependencyResolverDelegate {
    typealias Identifier = PackageReference
}

private let provider = MockPGProvider()
private let delegate = MockPGDelegate()

private let solver = PubgrubDependencyResolver(provider, delegate)

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

let fooRef = PackageReference(identity: "foo", path: "")
let barRef = PackageReference(identity: "bar", path: "")

let rootRef = PackageReference(identity: "root", path: "")
let rootCause = Incompatibility(Term(rootRef, .versionSet(.any)))



final class PubgrubTests: XCTestCase {
    override func setUp() {
        solver.reset()
    }

    func testTermInverse() {
        let t1 = Term(fooRef, .versionSet(.exact("1.0.0")))
        XCTAssertFalse(t1.inverse.isPositive)
        XCTAssertTrue(t1.inverse.inverse.isPositive)
    }

    func testTermSatisfies() {
        let tfoo: Term<PackageReference> = Term(fooRef, .versionSet(.exact("1.0.0")))

        XCTAssertFalse(tfoo.satisfies(
            other: Term(barRef, .unversioned)))
        XCTAssertTrue(tfoo.satisfies(other: tfoo))
        XCTAssertTrue(tfoo.satisfies(
            other: Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))))
        XCTAssertFalse(tfoo.satisfies(
            other: Term(fooRef, .versionSet(.range("2.0.0"..<"3.0.0")))))

        XCTAssertFalse(tfoo.satisfies(other: "¬foo@1.0.0"))
        XCTAssertFalse(tfoo.satisfies(other: "¬foo^1.0.0"))
        XCTAssertTrue(Term(not: fooRef, .versionSet(.exact("1.0.0"))).satisfies(other: "¬foo^1.0.0"))
        XCTAssertTrue(Term(not: fooRef, .versionSet(.exact("1.0.0"))).satisfies(other: "foo^2.0.0"))
        XCTAssertTrue(Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0"))).satisfies(other: "¬foo@2.0.0"))
        XCTAssertTrue(Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0"))).satisfies(other: "¬foo^2.0.0"))

        XCTAssertTrue(Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0"))).satisfies(
            other: Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))))
        XCTAssertTrue(Term(fooRef, .versionSet(.range("1.0.0"..<"1.1.0"))).satisfies(
            other: Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))))
        XCTAssertFalse(Term(fooRef, .versionSet(.range("1.0.0"..<"1.1.0"))).satisfies(
            other: Term(fooRef, .versionSet(.range("2.0.0"..<"3.0.0")))))

        XCTAssertTrue(Term(fooRef, .revision("foobar")).satisfies(
            other: Term(fooRef, .revision("foobar"))))
        XCTAssertFalse(Term(fooRef, .revision("foobar")).satisfies(
            other: Term(fooRef, .revision("barfoo"))))
    }

    func testTermIntersect() {
        // foo^1.0.0 ∩ ¬foo@1.5.0 → foo >=1.0.0 <1.5.0
        XCTAssertEqual(
            Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))
                .intersect(with: Term(not: fooRef, .versionSet(.exact("1.5.0")))),
            Term(fooRef, .versionSet(.range("1.0.0"..<"1.5.0"))))

        // foo^1.0.0 ∩ foo >=1.5.0 <3.0.0 → foo^1.5.0
        XCTAssertEqual(
            Term(fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))
                .intersect(with: Term(fooRef, .versionSet(.range("1.5.0"..<"3.0.0")))),
            Term(fooRef, .versionSet(.range("1.5.0"..<"2.0.0"))))

        // ¬foo^1.0.0 ∩ ¬foo >=1.5.0 <3.0.0 → ¬foo >=1.0.0 <3.0.0
        XCTAssertEqual(
            Term(not: fooRef, .versionSet(.range("1.0.0"..<"2.0.0")))
                .intersect(with: Term(not: fooRef, .versionSet(.range("1.5.0"..<"3.0.0")))),
            Term(not: fooRef, .versionSet(.range("1.0.0"..<"3.0.0"))))
    }

    func testTermIsValidDecision() {
        let cause = Incompatibility<PackageReference>("cause@0.0.0")

        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1)
        ])
        let t1: Term<PackageReference> = "a@1.5.0"
        XCTAssertTrue(t1.isValidDecision(for: s1))

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1),
            .decision("a^1.0.0", decisionLevel: 1)
        ])
        let t2: Term<PackageReference> = "a@1.5.0"
        XCTAssertFalse(t2.isValidDecision(for: s2))

        let s3 = PartialSolution(assignments: [
            .derivation("¬a@1.0.0", cause: cause, decisionLevel: 1)
        ])
        let t3: Term<PackageReference> = "a@1.0.0"
        XCTAssertFalse(t3.isValidDecision(for: s3))

        let s4 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1),
            .derivation("a^1.5.0", cause: cause, decisionLevel: 2)
        ])
        let t4: Term<PackageReference> = "a@1.6.0"
        XCTAssertTrue(t4.isValidDecision(for: s4))

        let s5 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1),
            .derivation("a^1.5.0", cause: cause, decisionLevel: 2)
        ])
        let t5: Term<PackageReference> = "a@1.2.0"
        XCTAssertFalse(t5.isValidDecision(for: s5))
    }

    func testSolutionPositive() {
        let s1 = PartialSolution<PackageReference>(assignments:[
            .decision("a^1.5.0", decisionLevel: 0),
            .decision("b@2.0.0", decisionLevel: 0),
            .decision("a^1.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s1.positive.count, 2)
        let a1 = s1.positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a1?.requirement, .versionSet(.range("1.5.0"..<"2.0.0")))
        let b1 = s1.positive.first { $0.key.identity == "b" }?.value
        XCTAssertEqual(b1?.requirement, .versionSet(.exact("2.0.0")))

        let s2 = PartialSolution<PackageReference>(assignments: [
            .decision("¬a^1.5.0", decisionLevel: 0),
            .decision("a^1.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s2.positive.count, 1)
        let a2 = s2.positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a2?.requirement, .versionSet(.range("1.0.0"..<"1.5.0")))
    }

    func testSolutionUnsatisfied() {
        let rootIncompat: Incompatibility<PackageReference> = Incompatibility(Term(rootRef, .versionSet(.any)))
        let s1 = PartialSolution<PackageReference>(assignments: [
            .derivation("a^1.5.0", cause: rootIncompat, decisionLevel: 0),
            .decision("b@2.0.0", decisionLevel: 0),
            .derivation("a^1.0.0", cause: rootIncompat, decisionLevel: 0)
        ])

        XCTAssertEqual(s1.unsatisfied, [Term("a", .versionSet(.range("1.5.0"..<"2.0.0")))])
    }

    func testSolutionSatisfiesIncompatibility() {
        let s1 = PartialSolution<PackageReference>(assignments: [
            .decision("foo@1.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s1.satisfies(Incompatibility("foo@1.0.0")), .satisfied)

        let s2 = PartialSolution<PackageReference>(assignments: [
            .decision("bar@2.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s2.satisfies(Incompatibility("¬foo@1.0.0", "bar@2.0.0")),
                       .almostSatisfied(except: "¬foo@1.0.0"))

        let s3 = PartialSolution<PackageReference>(assignments: [
            .decision("baz@3.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s3.satisfies(Incompatibility("¬foo@1.0.0", "bar@2.0.0")),
                       .unsatisfied)

        let s4 = PartialSolution<PackageReference>(assignments: [])
        XCTAssertEqual(s4.satisfies(Incompatibility("foo@1.0.0")), .unsatisfied)

        let s5 = PartialSolution<PackageReference>(assignments: [
            .decision("root@1.0.0", decisionLevel: 0),
            .decision("foo@0.1.0", decisionLevel: 0),
            .decision("bar@0.2.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s5.satisfies(Incompatibility("root@1.0.0", "bar@0.2.0")),
                       .satisfied)
    }

    func testSolutionAddAssignments() {
        let foo = Term(fooRef, .versionSet(.exact("1.0.0")))
        let bar = Term(barRef, .versionSet(.exact("2.0.0")))

        let solution = PartialSolution<PackageReference>(assignments: [])
        XCTAssertEqual(solution.decisionLevel, 0)
        solution.decide(foo)
        solution.derive(bar, cause: Incompatibility(foo))
        XCTAssertEqual(solution.decisionLevel, 2)

        XCTAssert(solution.assignments.contains(where: { $0.term == foo }))
        XCTAssert(solution.assignments.contains(where: { $0.term == bar }))
        XCTAssertEqual(solution.assignments.count, 2)
    }

    func testSolutionFindSatisfiers() {
        let s1 = PartialSolution<PackageReference>(assignments: [
            .decision("root@1.0.0", decisionLevel: 0),
            .decision("foo@0.1.0", decisionLevel: 0),
            .decision("bar@0.2.0", decisionLevel: 0)
        ])

        let rootAndbar = Incompatibility<PackageReference>("root@1.0.0", "bar@0.2.0")
        let (previous1, satisfier1) = s1.earliestSatisfiers(for: rootAndbar)
        XCTAssertEqual(previous1, Assignment.decision("root@1.0.0", decisionLevel: 0))
        XCTAssertEqual(satisfier1, Assignment.decision("bar@0.2.0", decisionLevel: 0))


        let s2 = PartialSolution<PackageReference>(assignments: [
            .decision("root@1.0.0", decisionLevel: 0),
            .decision("foo@0.1.0", decisionLevel: 0)
        ])

        let rootAndfoo = Incompatibility<PackageReference>("root@1.0.0", "foo@0.1.0")
        let (previous2, satisfier2) = s2.earliestSatisfiers(for: rootAndfoo)
        XCTAssertEqual(previous2, Assignment.decision("root@1.0.0", decisionLevel: 0))
        XCTAssertEqual(satisfier2, Assignment.decision("foo@0.1.0", decisionLevel: 0))


        let s3 = PartialSolution<PackageReference>(assignments: [
            .decision("root@1.0.0", decisionLevel: 0)
        ])

        let root = Incompatibility<PackageReference>("root@1.0.0")
        let (previous3, satisfier3) = s3.earliestSatisfiers(for: root)
        XCTAssertEqual(previous3, Assignment.decision("root@1.0.0", decisionLevel: 0))
        XCTAssertEqual(satisfier3, Assignment.decision("root@1.0.0", decisionLevel: 0))
    }

    func testSolutionBacktrack() {
        let solution = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 1),
            .decision("b@1.0.0", decisionLevel: 2),
            .decision("c@1.0.0", decisionLevel: 3),
        ])

        XCTAssertEqual(solution.assignments.count, 3)
        solution.backtrack(toDecisionLevel: 2)
        XCTAssertEqual(solution.assignments.count, 2)
        solution.backtrack(toDecisionLevel: 0)
        XCTAssertEqual(solution.assignments.count, 0)
    }

    func testSolutionVersionIntersection() {
        let cause = Incompatibility<PackageReference>("cause@0.0.0")

        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1),
        ])
        XCTAssertEqual(s1.versionIntersection(for: "a")?.requirement,
                       .versionSet(.range("1.0.0"..<"2.0.0")))

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: cause, decisionLevel: 1),
            .derivation("a^1.5.0", cause: cause, decisionLevel: 2)
        ])
        XCTAssertEqual(s2.versionIntersection(for: "a")?.requirement,
                       .versionSet(.range("1.5.0"..<"2.0.0")))
    }

    func testResolverAddIncompatibility() {
        XCTAssert(solver.incompatibilities.isEmpty)

        let fooIncompat = Incompatibility(Term(fooRef, .versionSet(.exact("1.0.0"))))
        solver.add(fooIncompat)
        XCTAssertEqual(solver.incompatibilities, ["foo": [fooIncompat]])

        let foobarIncompat = Incompatibility(
            Term(fooRef, .versionSet(.exact("1.0.0"))),
            Term(barRef, .versionSet(.exact("2.0.0")))
        )
        solver.add(foobarIncompat)
        XCTAssertEqual(solver.incompatibilities, [
            "foo": [fooIncompat, foobarIncompat],
            "bar": [foobarIncompat],
        ])
    }

    func testResolverUnitPropagation() {
        // no known incompatibilities should result in no satisfaction checks
        XCTAssertNil(solver.propagate("root"))

        // even if incompatibilities are present
        solver.add(Incompatibility(Term(fooRef, .versionSet(.exact("1.0.0")))))
        XCTAssertNil(solver.propagate("foo"))

        // adding a satisfying term should result in a conflict
        solver.solution.decide(Term(fooRef, .versionSet(.exact("1.0.0"))))
        XCTAssertEqual(solver.propagate(fooRef), Incompatibility(Term(fooRef, .versionSet(.exact("1.0.0")))))

        solver.reset()
        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        solver.add(Incompatibility(Term("root", .versionSet(.any)),
                                   Term(not: fooRef, .versionSet(.exact("1.0.0")))))
        solver.solution.decide(Term("root", .versionSet(.any)))

        XCTAssertEqual(solver.solution.assignments.count, 1)
        XCTAssertNil(solver.propagate(PackageReference(identity: "root", path: "")))
        XCTAssertEqual(solver.solution.assignments.count, 2)
    }

    func testResolverConflictResolution() {
        solver.root = rootRef

        let notRoot = Incompatibility(Term(not: rootRef, .versionSet(.any)), cause: .root)
        solver.add(notRoot)
        XCTAssertNil(solver.resolve(conflict: notRoot))

        solver.reset()
        solver.add(notRoot)
        solver.add(Incompatibility("foo^1.0.0", cause: .dependency(package: rootRef)))
        let resolved = solver.resolve(conflict: Incompatibility("foo^1.5.0"))
        XCTAssertEqual(resolved, Incompatibility(Term(fooRef, .versionSet(.range("1.5.0"..<"2.0.0")))))
    }

    func testResolverDecisionMaking() {
        solver.root = rootRef

        // No decision can be made if no unsatisfied terms are available.
        XCTAssertNil(try solver.makeDecision())

        let solution = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])
        solver.reset(solution: solution, root: rootRef)

        XCTAssertEqual(solver.incompatibilities.count, 1)

        solver.provider._register(package: "a", dependencies: ["b^1.0.0"])

        let decision = try! solver.makeDecision()
        XCTAssertEqual(decision, "a")

        XCTAssertEqual(solver.incompatibilities.count, 3)
        XCTAssertEqual(solver.incompatibilities["a"], [Incompatibility<PackageReference>("¬a@1.0.0", "b^1.0.0", cause: .dependency(package: "a"))])
    }
}

extension Term: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        var value = value

        var isPositive = true
        if value.hasPrefix("¬") {
            value.removeFirst()
            isPositive = false
        }

        var components: [String] = []
        var requirement: Requirement

        if value.contains("@") {
            components = value.split(separator: "@").map(String.init)
            requirement = .versionSet(.exact(Version(stringLiteral: components[1])))
        } else if value.contains("^") {
            components = value.split(separator: "^").map(String.init)
            let upperMajor = Int(String(components[1].split(separator: ".").first!))! + 1
            requirement = .versionSet(.range(Version(stringLiteral: components[1])..<Version(stringLiteral: "\(upperMajor).0.0")))
        } else {
            fatalError("Unrecognized format")
        }

        let packageReference: Identifier = PackageReference(identity: components[0], path: "") as! Identifier

        self.init(package: packageReference,
                  requirement: requirement,
                  isPositive: isPositive)
    }
}

extension PackageReference: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let ref = PackageReference(identity: value.lowercased(), path: "")
        self = ref
    }
}

private extension PubgrubDependencyResolver {
    /// Reset a PubgrubDependencyResolver's internal state.
    func reset(solution: PartialSolution<PackageReference> = PartialSolution(),
               incompatibilities: [PackageReference: [Incompatibility<PackageReference>]] = [:],
               changed: Set<PackageReference> = [],
               root: PackageReference? = nil) {
        self.solution = solution as! PartialSolution<D.Identifier>
        self.incompatibilities = incompatibilities as! [D.Identifier : [Incompatibility<D.Identifier>]]
        self.changed = changed as! Set<D.Identifier>
        self.root = root as? D.Identifier
    }
}
