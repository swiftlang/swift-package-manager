/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import TSCBasic
import PackageLoading
import PackageModel
import SourceControl

import PackageGraph

// There's some useful helper utilities defined below for easier testing:
//
// Terms conform to ExpressibleByStringLiteral in this test module and their
// version requirements can be created with a few options:
//   - "package@1.0.0": equivalent to .exact("1.0.0")
//   - "package^1.0.0": equivalent to .upToNextMajor("1.0.0")
//   - "package-1.0.0-3.0.0": equivalent to .range("1.0.0"..<"3.0.0")
//
// Mocking a dependency graph is easily achieved by using the builder API. It's
// a global object in this module.
//   builder.serve(dependencies: dependencies...)
// or for dependencies
//   builder.serve("packageName", at: someVersion, with: dependencies...)
// Calling builder.create() returns a resolver which can then be used to start
// the resolution by calling .solve() on it and passing a reference to the root
// package.
//
// The functions (AssertBindings,) AssertResult, AssertRootCause & AssertError
// can be used for checking the success or error outcomes of the resolver
// without having to manually pull the bindings or errors out of
// the results. They also offer useful failure messages.

let builder = DependencyGraphBuilder()

private let emptyProvider = MockProvider(containers: [])
private let delegate = _MockResolverDelegate()

private let v1: Version = "1.0.0"
private let v1_1: Version = "1.1.0"
private let v1_5: Version = "1.5.0"
private let v2: Version = "2.0.0"
private let v3: Version = "3.0.0"
private let v1Range: VersionSetSpecifier = .range(v1..<v2)
private let v1_5Range: VersionSetSpecifier = .range(v1_5..<v2)
private let v1to3Range: VersionSetSpecifier = .range(v1..<v3)
private let v2Range: VersionSetSpecifier = .range(v2..<v3)

let aRef = PackageReference(identity: "a", path: "")
let bRef = PackageReference(identity: "b", path: "")
let cRef = PackageReference(identity: "c", path: "")

let rootRef = PackageReference(identity: "root", path: "", kind: .root)
let rootNode = DependencyResolutionNode.root(package: rootRef)
let rootCause = Incompatibility(Term(rootNode, .exact(v1)), root: rootNode)
let _cause = Incompatibility("cause@0.0.0", root: rootNode)

final class PubgrubTests: XCTestCase {
    func testTermInverse() {
        let a = Term("a@1.0.0")
        XCTAssertFalse(a.inverse.isPositive)
        XCTAssertTrue(a.inverse.inverse.isPositive)
    }

    func testTermSatisfies() {
        let a100 = Term("a@1.0.0")

        XCTAssertTrue(a100.satisfies(a100))
        XCTAssertFalse(a100.satisfies("¬a@1.0.0"))
        XCTAssertTrue(a100.satisfies("a^1.0.0"))
        XCTAssertFalse(a100.satisfies("¬a^1.0.0"))
        XCTAssertFalse(a100.satisfies("a^2.0.0"))

        XCTAssertFalse(Term("¬a@1.0.0").satisfies("¬a^1.0.0"))
        XCTAssertFalse(Term("¬a@1.0.0").satisfies("a^2.0.0"))
        XCTAssertTrue(Term("¬a^1.0.0").satisfies("¬a@1.0.0"))
        XCTAssertTrue(Term("a^2.0.0").satisfies("¬a@1.0.0"))

        XCTAssertTrue(Term("a^1.0.0").satisfies("¬a@2.0.0"))
        XCTAssertTrue(Term("a^1.0.0").satisfies("¬a^2.0.0"))

        XCTAssertTrue(Term("a^1.0.0").satisfies(Term("a^1.0.0")))
        XCTAssertTrue(Term("a-1.0.0-1.1.0").satisfies(Term("a^1.0.0")))
        XCTAssertFalse(Term("a-1.0.0-1.1.0").satisfies(Term("a^2.0.0")))
    }

    func _testTermIntersection() {
        // a^1.0.0 ∩ ¬a@1.5.0 → a >=1.0.0 <1.5.0
        XCTAssertEqual(
            Term("a^1.0.0").intersect(with: Term("¬a@1.5.0")),
            Term("a-1.0.0-1.5.0"))

        // a^1.0.0 ∩ a >=1.5.0 <3.0.0 → a^1.5.0
        XCTAssertEqual(
            Term("a^1.0.0").intersect(with: Term("a-1.5.0-3.0.0")),
            Term("a^1.5.0"))

        // ¬a^1.0.0 ∩ ¬a >=1.5.0 <3.0.0 → ¬a >=1.0.0 <3.0.0
        XCTAssertEqual(
            Term("¬a^1.0.0").intersect(with: Term("¬a-1.5.0-3.0.0")),
            Term("¬a-1.0.0-3.0.0"))

        XCTAssertEqual(
            Term("a^1.0.0").intersect(with: Term("a^1.0.0")),
            Term("a^1.0.0"))

        XCTAssertEqual(
            Term("¬a^1.0.0").intersect(with: Term("¬a^1.0.0")),
            Term("¬a^1.0.0"))

        XCTAssertNil(Term("a^1.0.0").intersect(with: Term("¬a^1.0.0")))
        XCTAssertNil(Term("a@1.0.0").difference(with: Term("a@1.0.0")))

        XCTAssertEqual(
            Term("¬a^1.0.0").intersect(with: Term("a^2.0.0")),
            Term("a^2.0.0"))

        XCTAssertEqual(
            Term("a^2.0.0").intersect(with: Term("¬a^1.0.0")),
            Term("a^2.0.0"))

        XCTAssertEqual(
            Term("¬a^1.0.0").intersect(with: Term("¬a^1.0.0")),
            Term("¬a^1.0.0"))

        XCTAssertEqual(
            Term("¬a@1.0.0").intersect(with: Term("¬a@1.0.0")),
            Term("¬a@1.0.0"))

        // Check difference.
        let anyA = Term(.empty(package: "a"), .any)
        XCTAssertNil(Term("a^1.0.0").difference(with: anyA))

        let notEmptyA = Term(not: .empty(package: "a"), .empty)
        XCTAssertNil(Term("a^1.0.0").difference(with: notEmptyA))
    }

    func testTermRelation() {
        // Both positive.
        XCTAssertEqual(Term("a^1.1.0").relation(with: "a^1.0.0"), .subset)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a^1.8.9"), .subset)
        XCTAssertEqual(Term("a^1.5.0").relation(with: "a^1.0.0"), .subset)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a@1.9.0"), .overlap)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a@1.9.1"), .overlap)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a@1.20.0"), .overlap)
        XCTAssertEqual(Term("a^2.0.0").relation(with: "a^2.9.0"), .overlap)
        XCTAssertEqual(Term("a^2.0.0").relation(with: "a^2.9.0"), .overlap)
        XCTAssertEqual(Term("a-1.5.0-3.0.0").relation(with: "a^1.0.0"), .overlap)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a@1.8.1"), .disjoint)
        XCTAssertEqual(Term("a^1.9.0").relation(with: "a@2.0.0"), .disjoint)
        XCTAssertEqual(Term("a^2.0.0").relation(with: "a@1.0.0"), .disjoint)

        // First term is negative, second term is positive.
        XCTAssertEqual(Term("¬a^1.0.0").relation(with: "a@1.5.0"), .disjoint)
        XCTAssertEqual(Term("¬a^1.5.0").relation(with: "a^1.0.0"), .overlap)
        XCTAssertEqual(Term("¬a^2.0.0").relation(with: "a^1.5.0"), .overlap)

        // First term is positive, second term is negative.
        XCTAssertEqual(Term("a^2.0.0").relation(with: "¬a^1.0.0"), .subset)
        XCTAssertEqual(Term("a^1.5.0").relation(with: "¬a^1.0.0"), .disjoint)
        XCTAssertEqual(Term("a^1.0.0").relation(with: "¬a^1.5.0"), .overlap)
        XCTAssertEqual(Term("a-1.0.0-2.0.0").relation(with: "¬a-1.0.0-1.2.0"), .overlap)

        // Both terms are negative.
        XCTAssertEqual(Term("¬a^1.0.0").relation(with: "¬a^1.5.0"), .subset)
        XCTAssertEqual(Term("¬a^2.0.0").relation(with: "¬a^1.0.0"), .overlap)
        XCTAssertEqual(Term("¬a^1.5.0").relation(with: "¬a^1.0.0"), .overlap)
    }

    func testTermIsValidDecision() {
        let solution100_150 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 1),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 2)
        ])

        let allSatisfied = Term("a@1.6.0")
        XCTAssertTrue(allSatisfied.isValidDecision(for: solution100_150))
        let partiallySatisfied = Term("a@1.2.0")
        XCTAssertFalse(partiallySatisfied.isValidDecision(for: solution100_150))
    }

    func testIncompatibilityNormalizeTermsOnInit() {
        let i1 = Incompatibility(Term("a^1.0.0"), Term("a^1.5.0"), Term("¬b@1.0.0"),
                                 root: rootNode)
        XCTAssertEqual(i1.terms.count, 2)
        let a1 = i1.terms.first { $0.node.package == "a" }
        let b1 = i1.terms.first { $0.node.package == "b" }
        XCTAssertEqual(a1?.requirement, v1_5Range)
        XCTAssertEqual(b1?.requirement, .exact(v1))

        let i2 = Incompatibility(Term("¬a^1.0.0"), Term("a^2.0.0"),
                                 root: rootNode)
        XCTAssertEqual(i2.terms.count, 1)
        let a2 = i2.terms.first
        XCTAssertEqual(a2?.requirement, v2Range)
    }

    func testSolutionPositive() {
        let s1 = PartialSolution(assignments:[
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("b@2.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a1 = s1._positive.first { $0.key.package.identity == "a" }?.value
        XCTAssertEqual(a1?.requirement, v1_5Range)
        let b1 = s1._positive.first { $0.key.package.identity == "b" }?.value
        XCTAssertEqual(b1?.requirement, .exact(v2))

        let s2 = PartialSolution(assignments: [
            .derivation("¬a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a2 = s2._positive.first { $0.key.package.identity == "a" }?.value
        XCTAssertEqual(a2?.requirement, .range(v1..<v1_5))
    }

    func testSolutionUndecided() {
        let solution = PartialSolution()
        solution.derive("a^1.0.0", cause: rootCause)
        solution.decide(.empty(package: "b"), at: v2)
        solution.derive("a^1.5.0", cause: rootCause)
        solution.derive("¬c^1.5.0", cause: rootCause)
        solution.derive("d^1.9.0", cause: rootCause)
        solution.derive("d^1.9.9", cause: rootCause)

        let undecided = solution.undecided.sorted{ $0.node.package.identity < $1.node.package.identity }
        XCTAssertEqual(undecided, [Term("a^1.5.0"), Term("d^1.9.9")])
    }

    func testSolutionAddAssignments() {
        let root = Term(rootNode, .exact("1.0.0"))
        let a = Term("a@1.0.0")
        let b = Term("b@2.0.0")

        let solution = PartialSolution(assignments: [])
        solution.decide(rootNode, at: v1)
        solution.decide(.product("a", package: aRef), at: v1)
        solution.derive(b, cause: _cause)
        XCTAssertEqual(solution.decisionLevel, 1)

        XCTAssertEqual(solution.assignments, [
            .decision(root, decisionLevel: 0),
            .decision(a, decisionLevel: 1),
            .derivation(b, cause: _cause, decisionLevel: 1)
        ])
        XCTAssertEqual(solution.decisions, [
            rootNode: v1,
            .product("a", package: aRef): v1,
        ])
    }

    func testSolutionBacktrack() {
        // TODO: This should probably add derivations to cover that logic as well.
        let solution = PartialSolution()
        solution.decide(.empty(package: aRef), at: v1)
        solution.decide(.empty(package: bRef), at: v1)
        solution.decide(.empty(package: cRef), at: v1)

        XCTAssertEqual(solution.decisionLevel, 2)
        solution.backtrack(toDecisionLevel: 1)
        XCTAssertEqual(solution.assignments.count, 2)
        XCTAssertEqual(solution.decisionLevel, 1)
    }

    func testPositiveTerms() {
        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
        ])
        XCTAssertEqual(s1._positive[.product("a", package: "a")]?.requirement,
                       v1Range)

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0)
        ])
        XCTAssertEqual(s2._positive[.product("a", package: "a")]?.requirement,
                       v1_5Range)
    }

    func testResolverAddIncompatibility() {
        let solver = PubgrubDependencyResolver(emptyProvider, delegate)

        let a = Incompatibility(Term("a@1.0.0"), root: rootNode)
        solver.add(a, location: .topLevel)
        let ab = Incompatibility(Term("a@1.0.0"), Term("b@2.0.0"), root: rootNode)
        solver.add(ab, location: .topLevel)

        XCTAssertEqual(solver.incompatibilities, [
            .product("a", package: "a"): [a, ab],
            .product("b", package: "b"): [ab],
        ])
    }

    func testUpdatePackageIdentifierAfterResolution() {
        let fooRef = PackageReference(identity: "foo", path: "https://some.url/FooBar")
        let foo = MockContainer(name: fooRef, dependenciesByVersion: [v1: [:]])
        foo.manifestName = "bar"

        let provider = MockProvider(containers: [foo])

        let resolver = PubgrubDependencyResolver(provider, delegate)
        let deps = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"]))
        ])
        let result = resolver.solve(dependencies: deps)

        switch result {
        case .error(let error):
            XCTFail("Unexpected error: \(error)")
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 1)
            let foo = bindings.first { $0.container.identity == "foo" }
            XCTAssertEqual(foo?.container.name, "bar")
        }
    }

    func testResolverConflictResolution() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.set(rootNode)

        let notRoot = Incompatibility(Term(not: rootNode, .any),
                                      root: rootNode,
                                      cause: .root)
        solver1.add(notRoot, location: .topLevel)
        XCTAssertThrowsError(try solver1._resolve(conflict: notRoot))
    }

    func testResolverDecisionMaking() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.set(rootNode)

        // No decision can be made if no unsatisfied terms are available.
        XCTAssertNil(try solver1.makeDecision())

        let a = MockContainer(name: aRef, dependenciesByVersion: [
            "0.0.0": [:],
            v1: ["a": [(package: bRef, requirement: v1Range, productFilter: .specific(["b"]))]]
        ])

        let provider = MockProvider(containers: [a])
        let solver2 = PubgrubDependencyResolver(provider, delegate)
        let solution = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])
        solver2.solution = solution
        solver2.set(rootNode)

        XCTAssertEqual(solver2.incompatibilities.count, 0)

        let decision = try! solver2.makeDecision()
        XCTAssertEqual(decision, .product("a", package: "a"))

        XCTAssertEqual(solver2.incompatibilities.count, 3)
        XCTAssertEqual(solver2.incompatibilities[.product("a", package: "a")], [
            Incompatibility("a^1.0.0", Term(not: .product("b", package: "b"), v1Range),
                                              root: rootNode,
                                              cause: .dependency(node: .product("a", package: "a"))),
            Incompatibility("a^1.0.0", Term(not: .empty(package: "a"), .exact("1.0.0")),
                                              root: rootNode,
                                              cause: .dependency(node: .product("a", package: "a"))),
        ])
    }

    func testResolverUnitPropagation() throws {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)

        // no known incompatibilities should result in no satisfaction checks
        try solver1.propagate(.root(package: "root"))

        // even if incompatibilities are present
        solver1.add(Incompatibility(Term("a@1.0.0"), root: rootNode), location: .topLevel)
        try solver1.propagate(.empty(package: "a"))
        try solver1.propagate(.empty(package: "a"))
        try solver1.propagate(.empty(package: "a"))

        // adding a satisfying term should result in a conflict
        solver1.solution.decide(.empty(package: aRef), at: v1)
        // FIXME: This leads to fatal error.
        // try solver1.propagate(aRef)

        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        let solver2 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver2.add(Incompatibility(Term(.root(package: "root"), .any),
                                    Term("¬a@1.0.0"),
                                    root: rootNode), location: .topLevel)
        solver2.solution.decide(rootNode, at: v1)
        XCTAssertEqual(solver2.solution.assignments.count, 1)
        try solver2.propagate(.root(package: PackageReference(identity: "root", path: "")))
        XCTAssertEqual(solver2.solution.assignments.count, 2)
    }

    func testSolutionFindSatisfiers() {
        let solution = PartialSolution()
        solution.decide(rootNode, at: v1) // ← previous, but actually nil because this is the root decision
        solution.derive(Term(.product("a", package: aRef), .any), cause: _cause) // ← satisfier
        solution.decide(.product("a", package: aRef), at: v2)
        solution.derive("b^1.0.0", cause: _cause)

        XCTAssertEqual(solution.satisfier(for: Term("b^1.0.0")) .term, "b^1.0.0")
        XCTAssertEqual(solution.satisfier(for: Term("¬a^1.0.0")).term, "a@2.0.0")
        XCTAssertEqual(solution.satisfier(for: Term("a^2.0.0")).term, "a@2.0.0")
    }

    func testResolutionNoConflicts() {
        builder.serve("a", at: v1, with: ["a": ["b": (.versionSet(v1Range), .specific(["b"]))]])
        builder.serve("b", at: v1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1))
        ])
    }

    func testResolutionAvoidingConflictResolutionDuringDecisionMaking() {
        builder.serve("a", at: v1)
        builder.serve("a", at: v1_1, with: ["a": ["b": (.versionSet(v2Range), .specific(["b"]))]])
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
            "b": (.versionSet(v1Range), .specific(["b"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version("1.1.0"))
        ])
    }

    func testResolutionPerformingConflictResolution() {
        // Pubgrub has a listed as >=1.0.0, which we can't really represent here.
        // It's either .any or 1.0.0..<n.0.0 with n>2. Both should have the same
        // effect though.
        builder.serve("a", at: v1)
        builder.serve("a", at: v2, with: ["a": ["b": (.versionSet(v1Range), .specific(["b"]))]])
        builder.serve("b", at: v1, with: ["b": ["a": (.versionSet(v1Range), .specific(["a"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1to3Range), .specific(["a"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1))
        ])
    }

    func testResolutionConflictResolutionWithAPartialSatisfier() {
        builder.serve("foo", at: v1)
        builder.serve("foo", at: v1_1, with: [
            "foo": ["left": (.versionSet(v1Range), .specific(["left"]))],
            "foo": ["right": (.versionSet(v1Range), .specific(["right"]))]
        ])
        builder.serve("left", at: v1, with: ["left": ["shared": (.versionSet(v1Range), .specific(["shared"]))]])
        builder.serve("right", at: v1, with: ["right": ["shared": (.versionSet(v1Range), .specific(["shared"]))]])
        builder.serve("shared", at: v1, with: ["shared": ["target": (.versionSet(v1Range), .specific(["target"]))]])
        builder.serve("shared", at: v2)
        builder.serve("target", at: v1)
        builder.serve("target", at: v2)

        // foo 1.1.0 transitively depends on a version of target that's not compatible
        // with root's constraint. This dependency only exists because of left
        // *and* right, choosing only one of these would be fine.

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
            "target": (.versionSet(v2Range), .specific(["target"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .version(v1)),
            ("target", .version(v2))
        ])
    }

    func testCycle1() {
        builder.serve("foo", at: v1_1, with: ["foo": ["foo": (.versionSet(v1Range), .specific(["foo"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .version(v1_1)),
        ])
    }

    func testCycle2() {
        builder.serve("foo", at: v1_1, with: ["foo": ["bar": (.versionSet(v1Range), .specific(["bar"]))]])
        builder.serve("bar", at: v1, with: ["bar": ["baz": (.versionSet(v1Range), .specific(["baz"]))]])
        builder.serve("baz", at: v1, with: ["baz": ["bam": (.versionSet(v1Range), .specific(["bam"]))]])
        builder.serve("bam", at: v1, with: ["bam": ["baz": (.versionSet(v1Range), .specific(["baz"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .version(v1_1)),
            ("bar", .version(v1)),
            ("baz", .version(v1)),
            ("bam", .version(v1)),
        ])
    }

    func testLocalPackageCycle() {
        builder.serve("foo", at: .unversioned, with: [
            "foo": ["bar": (.unversioned, .specific(["bar"]))],
        ])
        builder.serve("bar", at: .unversioned, with: [
            "bar": ["baz": (.unversioned, .specific(["baz"]))],
        ])
        builder.serve("baz", at: .unversioned, with: [
            "baz": ["foo": (.unversioned, .specific(["foo"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .unversioned),
            ("baz", .unversioned),
        ])
    }

    func testBranchBasedPackageCycle() {
        builder.serve("foo", at: .revision("develop"), with: [
            "foo": ["bar": (.revision("develop"), .specific(["bar"]))],
        ])
        builder.serve("bar", at: .revision("develop"), with: [
            "bar": ["baz": (.revision("develop"), .specific(["baz"]))],
        ])
        builder.serve("baz", at: .revision("develop"), with: [
            "baz": ["foo": (.revision("develop"), .specific(["foo"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("develop"), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("develop")),
            ("bar", .revision("develop")),
            ("baz", .revision("develop")),
        ])
    }

    func testNonExistentPackage() {
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "package": (.versionSet(.exact(v1)), .specific(["package"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertError(result, _MockLoadingError.unknownModule)
    }

    func testUnversioned1() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: v1_5)
        builder.serve("bar", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
            "bar": (.versionSet(v1Range), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1_5))
        ])
    }

    func testUnversioned2() {
        builder.serve("foo", at: .unversioned, with: [
            "foo": ["bar": (.versionSet(.range(v1..<"1.2.0")), .specific(["bar"]))]
        ])
        builder.serve("bar", at: v1)
        builder.serve("bar", at: v1_1)
        builder.serve("bar", at: v1_5)
        builder.serve("bar", at: v2)

        let resolver = builder.create()

        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
            "bar": (.versionSet(v1Range), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1_1))
        ])
    }

    func testUnversioned3() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: v1, with: [
            "bar": ["foo": (.versionSet(.exact(v1)), .specific(["foo"]))]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
            "bar": (.versionSet(v1Range), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1))
        ])
    }

    func testUnversioned4() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: .revision("master"), with: [
            "bar": ["foo": (.versionSet(v1Range), .specific(["foo"]))]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
            "bar": (.revision("master"), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .revision("master"))
        ])
    }

    func testUnversioned5() {
        builder.serve("foo", at: .unversioned)
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: .revision("master"), with: [
            "bar": ["foo": (.revision("master"), .specific(["foo"]))]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned, .specific(["foo"])),
            "bar": (.revision("master"), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .revision("master"))
        ])
    }

    func testUnversioned7() {
        builder.serve("local", at: .unversioned, with: [
            "local": ["remote": (.unversioned, .specific(["remote"]))]
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "local": (.unversioned, .specific(["local"])),
            "remote": (.versionSet(v1Range), .specific(["remote"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("remote", .unversioned),
            ("local", .unversioned)
        ])
    }

    func testUnversioned8() {
        builder.serve("entry", at: .unversioned, with: [
            "entry": [
                "remote": (.versionSet(v1Range), .specific(["remote"])),
                "local": (.unversioned, .specific(["local"])),
            ]
        ])
        builder.serve("local", at: .unversioned, with: [
            "local": ["remote": (.unversioned, .specific(["remote"]))]
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "entry": (.unversioned, .specific(["entry"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("entry", .unversioned),
            ("local", .unversioned),
            ("remote", .unversioned),
        ])
    }

    func testUnversioned9() {
        builder.serve("entry", at: .unversioned, with: [
            "entry": [
                "local": (.unversioned, .specific(["local"])),
                "remote": (.versionSet(v1Range), .specific(["remote"])),
            ]
        ])
        builder.serve("local", at: .unversioned, with: [
            "local": ["remote": (.unversioned, .specific(["remote"]))]
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "entry": (.unversioned, .specific(["entry"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("entry", .unversioned),
            ("local", .unversioned),
            ("remote", .unversioned),
        ])
    }

    func testResolutionWithSimpleBranchBasedDependency() {
        builder.serve("foo", at: .revision("master"), with: ["foo": ["bar": (.versionSet(v1Range), .specific(["bar"]))]])
        builder.serve("bar", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"])),
            "bar": (.versionSet(v1Range), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithSimpleBranchBasedDependency2() {
        builder.serve("foo", at: .revision("master"), with: ["foo": ["bar": (.versionSet(v1Range), .specific(["bar"]))]])
        builder.serve("bar", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency() {
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: v1, with: ["bar": ["foo": (.versionSet(v1Range), .specific(["foo"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"])),
            "bar": (.versionSet(.exact(v1)), .specific(["bar"])),

        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency2() {
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: v1, with: ["bar": ["foo": (.versionSet(v1Range), .specific(["foo"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.exact(v1)), .specific(["bar"])),
            "foo": (.revision("master"), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency3() {
        builder.serve("foo", at: .revision("master"), with: ["foo": ["bar": (.revision("master"), .specific(["bar"]))]])

        builder.serve("bar", at: .revision("master"))
        builder.serve("bar", at: v1)

        builder.serve("baz", at: .revision("master"), with: ["baz": ["bar": (.versionSet(v1Range), .specific(["bar"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"])),
            "baz": (.revision("master"), .specific(["baz"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .revision("master")),
            ("baz", .revision("master")),
        ])
    }

    func testResolutionWithUnavailableRevision() {
        builder.serve("foo", at: .version(v1))

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertError(result, _MockLoadingError.unknownRevision)
    }

    func testResolutionWithRevisionConflict() {
        builder.serve("foo", at: .revision("master"), with: ["foo": ["bar": (.revision("master"), .specific(["bar"]))]])
        builder.serve("bar", at: .version(v1))
        builder.serve("bar", at: .revision("master"))

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(v1Range), .specific(["bar"])),
            "foo": (.revision("master"), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .revision("master")),
        ])
    }

    func testBranchOverriding3() {
        builder.serve("swift-nio", at: v1)
        builder.serve("swift-nio", at: .revision("master"))
        builder.serve("swift-nio-ssl", at: .revision("master"), with: [
            "swift-nio-ssl": ["swift-nio": (.versionSet(v2Range), .specific(["swift-nio"]))],
        ])
        builder.serve("foo", at: "1.0.0", with: [
            "foo": ["swift-nio": (.versionSet(v1Range), .specific(["swift-nio"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
            "swift-nio": (.revision("master"), .specific(["swift-nio"])),
            "swift-nio-ssl": (.revision("master"), .specific(["swift-nio-ssl"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("swift-nio-ssl", .revision("master")),
            ("swift-nio", .revision("master")),
            ("foo", .version(v1))
        ])
    }

    func testBranchOverriding4() {
        builder.serve("swift-nio", at: v1)
        builder.serve("swift-nio", at: .revision("master"))
        builder.serve("swift-nio-ssl", at: .revision("master"), with: [
            "swift-nio-ssl": ["swift-nio": (.versionSet(v2Range), .specific(["swift-nio"]))],
        ])
        builder.serve("nio-postgres", at: .revision("master"), with: [
            "nio-postgres": [
                "swift-nio": (.revision("master"), .specific(["swift-nio"])),
                "swift-nio-ssl": (.revision("master"), .specific(["swift-nio-ssl"])),
            ]
        ])
        builder.serve("http-client", at: v1, with: [
            "http-client": [
                "swift-nio": (.versionSet(v1Range), .specific(["swift-nio"])),
                "boring-ssl": (.versionSet(v1Range), .specific(["boring-ssl"])),
            ]
        ])
        builder.serve("boring-ssl", at: v1, with: [
            "boring-ssl": ["swift-nio": (.versionSet(v1Range), .specific(["swift-nio"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "nio-postgres": (.revision("master"), .specific(["nio-postgres"])),
            "http-client": (.versionSet(v1Range), .specific(["https-client"])),
            "boring-ssl": (.versionSet(v1Range), .specific(["boring-ssl"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("swift-nio-ssl", .revision("master")),
            ("swift-nio", .revision("master")),
            ("nio-postgres", .revision("master")),
            ("http-client", .version(v1)),
            ("boring-ssl", .version(v1)),
        ])
    }

    func testNonVersionDependencyInVersionDependency2() {
        builder.serve("foo", at: v1_1, with: [
            "foo": ["bar": (.revision("master"), .specific(["bar"]))]
        ])
        builder.serve("foo", at: v1)
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .version(v1)),
        ])
    }

    func testTrivialPinStore() {
        builder.serve("a", at: v1, with: ["a": ["b": (.versionSet(v1Range), .specific(["b"]))]])
        builder.serve("a", at: v1_1)
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
        ])

        let pinsStore = builder.create(pinsStore: [
            "a": (.version(v1), .specific(["a"])),
            "b": (.version(v1), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies, pinsMap: pinsStore.pinsMap)

        // Since a was pinned, we shouldn't have computed bounds for its incomaptibilities.
        let aIncompat = resolver.positiveIncompatibilities(for: .product("a", package: builder.reference(for: "a")))![0]
        XCTAssertEqual(aIncompat.terms[0].requirement, .exact("1.0.0"))

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1))
        ])
    }

    func testPartialPins() {
        // This checks that we can drop pins that are not valid anymore but still keep the ones
        // which fit the constraints.
        builder.serve("a", at: v1, with: ["a": ["b": (.versionSet(v1Range), .specific(["b"]))]])
        builder.serve("a", at: v1_1)
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("c", at: v1, with: ["c": ["b": (.versionSet(.range(v1_1..<v2)), .specific(["b"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(v1Range), .specific(["c"])),
            "a": (.versionSet(v1Range), .specific(["a"])),
        ])

        // Here b is pinned to v1 but its requirement is now 1.1.0..<2.0.0 in the graph
        // due to addition of a new dependency.
        let pinsStore = builder.create(pinsStore: [
            "a": (.version(v1), .specific(["a"])),
            "b": (.version(v1), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies, pinsMap: pinsStore.pinsMap)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1_1)),
            ("c", .version(v1))
        ])
    }

    func testBranchedBasedPin() {
        // This test ensures that we get the SHA listed in Package.resolved for branch-based
        // dependencies.
        builder.serve("a", at: .revision("develop-sha-1"))
        builder.serve("b", at: .revision("master-sha-2"))

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.revision("develop"), .specific(["a"])),
            "b": (.revision("master"), .specific(["b"])),
        ])

        let pinsStore = builder.create(pinsStore: [
            "a": (.branch("develop", revision: "develop-sha-1"), .specific(["a"])),
            "b": (.branch("master", revision: "master-sha-2"), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies, pinsMap: pinsStore.pinsMap)

        AssertResult(result, [
            ("a", .revision("develop")),
            ("b", .revision("master")),
        ])
    }

    func testIncompatibleToolsVersion2() {
        builder.serve("a", at: v1_1, isToolsVersionCompatible: false)
        builder.serve("a", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
        ])
    }

    func testUnreachableProductsSkipped() {
        builder.serve("root", at: .unversioned, with: [
            "root": ["immediate": (.versionSet(v1Range), .specific(["ImmediateUsed"]))]
        ])
        builder.serve("immediate", at: v1, with: [
            "ImmediateUsed": ["transitive": (.versionSet(v1Range), .specific(["TransitiveUsed"]))],
            "ImmediateUnused": [
                "transitive": (.versionSet(v1Range), .specific(["TransitiveUnused"])),
                "nonexistent": (.versionSet(v1Range), .specific(["Nonexistent"]))
            ]
        ])
        builder.serve("transitive", at: v1, with: [
            "TransitiveUsed": [:],
            "TransitiveUnused": [
                "nonexistent": (.versionSet(v1Range), .specific(["Nonexistent"]))
            ]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "root": (.unversioned, .everything)
        ])
        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("root", .unversioned),
            ("immediate", .version(v1)),
            ("transitive", .version(v1))
        ])
    }
}

final class PubGrubTestsBasicGraphs: XCTestCase {
    func testSimple1() {
        builder.serve("a", at: v1, with: [
            "a": [
                "aa": (.versionSet(.exact("1.0.0")), .specific(["aa"])),
                "ab": (.versionSet(.exact("1.0.0")), .specific(["ab"])),
            ]
        ])
        builder.serve("aa", at: v1)
        builder.serve("ab", at: v1)
        builder.serve("b", at: v1, with: [
            "b": [
                "ba": (.versionSet(.exact("1.0.0")), .specific(["ba"])),
                "bb": (.versionSet(.exact("1.0.0")), .specific(["bb"])),
            ]
        ])
        builder.serve("ba", at: v1)
        builder.serve("bb", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.exact("1.0.0")), .specific(["a"])),
            "b": (.versionSet(.exact("1.0.0")), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies)
        AssertResult(result, [
            ("a", .version(v1)),
            ("aa", .version(v1)),
            ("ab", .version(v1)),
            ("b", .version(v1)),
            ("ba", .version(v1)),
            ("bb", .version(v1)),
        ])
    }

    func testSharedDependency1() {
        builder.serve("a", at: v1, with: [
            "a": ["shared": (.versionSet(.range("2.0.0"..<"4.0.0")), .specific(["shared"]))],
        ])
        builder.serve("b", at: v1, with: [
            "b": ["shared": (.versionSet(.range("3.0.0"..<"5.0.0")), .specific(["shared"]))],
        ])
        builder.serve("shared", at: "2.0.0")
        builder.serve("shared", at: "3.0.0")
        builder.serve("shared", at: "3.6.9")
        builder.serve("shared", at: "4.0.0")
        builder.serve("shared", at: "5.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.exact("1.0.0")), .specific(["a"])),
            "b": (.versionSet(.exact("1.0.0")), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies)
        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1)),
            ("shared", .version("3.6.9")),
        ])
    }

    func testSharedDependency2() {
        builder.serve("foo", at: "1.0.0")
        builder.serve("foo", at: "1.0.1", with: [
            "foo": ["bang": (.versionSet(.exact("1.0.0")), .specific(["bang"]))],
        ])
        builder.serve("foo", at: "1.0.2", with: [
            "foo": ["whoop": (.versionSet(.exact("1.0.0")), .specific(["whoop"]))],
        ])
        builder.serve("foo", at: "1.0.3", with: [
            "foo": ["zoop": (.versionSet(.exact("1.0.0")), .specific(["zoop"]))],
        ])
        builder.serve("bar", at: "1.0.0", with: [
            "bar": ["foo": (.versionSet(.range("0.0.0"..<"1.0.2")), .specific(["foo"]))],
        ])
        builder.serve("bang", at: "1.0.0")
        builder.serve("whoop", at: "1.0.0")
        builder.serve("zoop", at: "1.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.range("0.0.0"..<"1.0.3")), .specific(["foo"])),
            "bar": (.versionSet(.exact("1.0.0")), .specific(["bar"])),
        ])

        let result = resolver.solve(dependencies: dependencies)
        AssertResult(result, [
            ("foo", .version("1.0.1")),
            ("bar", .version(v1)),
            ("bang", .version(v1)),
        ])
    }

    func testFallbacksToOlderVersion() {
        builder.serve("foo", at: "1.0.0")
        builder.serve("foo", at: "2.0.0")
        builder.serve("bar", at: "1.0.0")
        builder.serve("bar", at: "2.0.0", with: [
            "bar": ["baz": (.versionSet(.exact("1.0.0")), .specific(["baz"]))],
        ])
        builder.serve("baz", at: "1.0.0", with: [
            "baz": ["foo": (.versionSet(.exact("2.0.0")), .specific(["foo"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["bar"])),
            "foo": (.versionSet(.exact("1.0.0")), .specific(["foo"])),
        ])

        let result = resolver.solve(dependencies: dependencies)
        AssertResult(result, [
            ("foo", .version(v1)),
            ("bar", .version(v1)),
        ])
    }
}

final class PubGrubDiagnosticsTests: XCTestCase {

    func testMissingVersion() {
        builder.serve("foopkg", at: v1_1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foopkg": (.versionSet(v2Range), .specific(["foopkg"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "because no versions of foopkg[foopkg] match the requirement 2.0.0..<3.0.0 and root depends on foopkg[foopkg] 2.0.0..<3.0.0, version solving failed.")
    }

    func testResolutionNonExistentVersion() {
        builder.serve("package", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "package": (.versionSet(.exact(v1)), .specific(["package"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "because no versions of package[package] match the requirement 1.0.0 and root depends on package[package] 1.0.0, version solving failed.")
    }

    func testResolutionLinearErrorReporting() {
        builder.serve("foo", at: v1, with: ["foo": ["bar": (.versionSet(v2Range), .specific(["bar"]))]])
        builder.serve("bar", at: v2, with: ["bar": ["baz": (.versionSet(.range("3.0.0"..<"4.0.0")), .specific(["baz"]))]])
        builder.serve("baz", at: v1)
        builder.serve("baz", at: "3.0.0")

        // root transitively depends on a version of baz that's not compatible
        // with root's constraint.

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
            "baz": (.versionSet(v1Range), .specific(["baz"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because every version of foo[foo] depends on bar[bar] 2.0.0..<3.0.0 and every version of bar[bar] depends on baz[baz] 3.0.0..<4.0.0, every version of foo[foo] requires baz[baz] 3.0.0..<4.0.0.
            And because root depends on foo[foo] 1.0.0..<2.0.0 and root depends on baz[baz] 1.0.0..<2.0.0, version solving failed.
            """)
    }

    func testResolutionBranchingErrorReporting() {
        builder.serve("foo", at: v1, with: [
            "foo": [
                "a": (.versionSet(v1Range), .specific(["a"])),
                "b": (.versionSet(v1Range), .specific(["b"]))
            ]
        ])
        builder.serve("foo", at: v1_1, with: [
            "foo": [
                "x": (.versionSet(v1Range), .specific(["x"])),
                "y": (.versionSet(v1Range), .specific(["y"]))
            ]
        ])
        builder.serve("a", at: v1, with: ["a": ["b": (.versionSet(v2Range), .specific(["b"]))]])
        builder.serve("b", at: v1)
        builder.serve("b", at: v2)
        builder.serve("x", at: v1, with: ["x": ["y": (.versionSet(v2Range), .specific(["y"]))]])
        builder.serve("y", at: v1)
        builder.serve("y", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
          because every version of a[a] depends on b[b] 2.0.0..<3.0.0 and foo[foo] <1.1.0 depends on a[a] 1.0.0..<2.0.0, foo[foo] <1.1.0 requires b[b] 2.0.0..<3.0.0.
             (1) So, because foo[foo] <1.1.0 depends on b[b] 1.0.0..<2.0.0, foo[foo] <1.1.0 is forbidden.
          because every version of x[x] depends on y[y] 2.0.0..<3.0.0 and foo[foo] >=1.1.0 depends on x[x] 1.0.0..<2.0.0, foo[foo] >=1.1.0 requires y[y] 2.0.0..<3.0.0.
          And because foo[foo] >=1.1.0 depends on y[y] 1.0.0..<2.0.0, foo[foo] >=1.1.0 is forbidden.
          And because foo[foo] <1.1.0 is forbidden (1), foo[foo] is forbidden.
          And because root depends on foo[foo] 1.0.0..<2.0.0, version solving failed.
        """)
    }

    func testConflict1() {
        builder.serve("foo", at: v1, with: ["foo": ["config": (.versionSet(v1Range), .specific(["config"]))]])
        builder.serve("bar", at: v1, with: ["bar": ["config": (.versionSet(v2Range), .specific(["config"]))]])
        builder.serve("config", at: v1)
        builder.serve("config", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
            "bar": (.versionSet(v1Range), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because every version of bar[bar] depends on config[config] 2.0.0..<3.0.0 and every version of foo[foo] depends on config[config] 1.0.0..<2.0.0, bar[bar] is incompatible with foo[foo].
            And because root depends on foo[foo] 1.0.0..<2.0.0 and root depends on bar[bar] 1.0.0..<2.0.0, version solving failed.
            """)
    }

    func testConflict2() {
        func addDeps() {
            builder.serve("foo", at: v1, with: ["foo": ["config": (.versionSet(v1Range), .specific(["config"]))]])
            builder.serve("config", at: v1)
            builder.serve("config", at: v2)
        }

        let dependencies1 = builder.create(dependencies: [
            "config": (.versionSet(v2Range), .specific(["config"])),
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        addDeps()
        let resolver1 = builder.create()
        let result1 = resolver1.solve(dependencies: dependencies1)

        XCTAssertEqual(result1.errorMsg, """
            because every version of foo[foo] depends on config[config] 1.0.0..<2.0.0 and root depends on config[config] 2.0.0..<3.0.0, foo[foo] is forbidden.
            And because root depends on foo[foo] 1.0.0..<2.0.0, version solving failed.
            """)

        let dependencies2 = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
            "config": (.versionSet(v2Range), .specific(["config"])),
        ])
        addDeps()
        let resolver2 = builder.create()
        let result2 = resolver2.solve(dependencies: dependencies2)

        XCTAssertEqual(result2.errorMsg, """
            because every version of foo[foo] depends on config[config] 1.0.0..<2.0.0 and root depends on foo[foo] 1.0.0..<2.0.0, config[config] 1.0.0..<2.0.0 is required.
            And because root depends on config[config] 2.0.0..<3.0.0, version solving failed.
            """)
    }

    func testConflict3() {
        builder.serve("foo", at: v1, with: ["foo": ["config": (.versionSet(v1Range), .specific(["config"]))]])
        builder.serve("config", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "config": (.versionSet(v2Range), .specific(["config"])),
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "because no versions of config[config] match the requirement 2.0.0..<3.0.0 and root depends on config[config] 2.0.0..<3.0.0, version solving failed.")
    }

    func testUnversioned6() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: .revision("master"), with: [
            "bar": ["foo": (.unversioned, .specific(["foo"]))]
        ])

        let resolver = builder.create()

        let dependencies = builder.create(dependencies: [
            "bar": (.revision("master"), .specific(["bar"]))
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "package 'bar' is required using a revision-based requirement and it depends on local package 'foo', which is not supported")
    }

    func testResolutionWithOverridingBranchBasedDependency4() {
        builder.serve("foo", at: .revision("master"), with: ["foo": ["bar": (.revision("master"), .specific(["bar"]))]])

        builder.serve("bar", at: .revision("master"))
        builder.serve("bar", at: v1)

        builder.serve("baz", at: .revision("master"), with: ["baz": ["bar": (.revision("develop"), .specific(["baz"]))]])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master"), .specific(["foo"])),
            "baz": (.revision("master"), .specific(["baz"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "bar is required using two different revision-based requirements (master and develop), which is not supported")
    }

    func testNonVersionDependencyInVersionDependency1() {
        builder.serve("foo", at: v1_1, with: [
            "foo": ["bar": (.revision("master"), .specific(["bar"]))]
        ])
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because no versions of foo[foo] match the requirement {1.0.0..<1.1.0, 1.1.1..<2.0.0} and package foo is required using a version-based requirement and it depends on unversion package bar, foo[foo] is forbidden.
            And because root depends on foo[foo] 1.0.0..<2.0.0, version solving failed.
            """)
    }

    func testNonVersionDependencyInVersionDependency3() {
        builder.serve("foo", at: v1, with: [
            "foo": ["bar": (.unversioned, .specific(["bar"]))]
        ])
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.exact(v1)), .specific(["foo"])),
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, "because package foo is required using a version-based requirement and it depends on unversion package bar and root depends on foo[foo] 1.0.0, version solving failed.")
    }

    func testIncompatibleToolsVersion1() {
        builder.serve("a", at: v1, isToolsVersionCompatible: false)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because no versions of a[a] match the requirement 1.0.1..<2.0.0 and a[a] 1.0.0 contains incompatible tools version, a[a] >=1.0.0 is forbidden.
            And because root depends on a[a] 1.0.0..<2.0.0, version solving failed.
            """)
    }

    func testIncompatibleToolsVersion3() {
        builder.serve("a", at: v1_1, with: [
            "a": ["b": (.versionSet(v1Range), .specific(["b"]))]
        ])
        builder.serve("a", at: v1, isToolsVersionCompatible: false)

        builder.serve("b", at: v1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range), .specific(["a"])),
            "b": (.versionSet(v2Range), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because no versions of a[a] match the requirement 1.0.1..<1.1.0 and a[a] 1.0.0 contains incompatible tools version, a[a] 1.0.0..<1.1.0 is forbidden.
            And because a[a] >=1.1.0 depends on b[b] 1.0.0..<2.0.0, a[a] >=1.0.0 requires b[b] 1.0.0..<2.0.0.
            And because root depends on a[a] 1.0.0..<2.0.0 and root depends on b[b] 2.0.0..<3.0.0, version solving failed.
            """)
    }

    func testIncompatibleToolsVersion4() {
        builder.serve("a", at: "3.2.1", isToolsVersionCompatible: false)
        builder.serve("a", at: "3.2.2", isToolsVersionCompatible: false)
        builder.serve("a", at: "3.2.3", isToolsVersionCompatible: false)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0")), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because every version of a[a] contains incompatible tools version and root depends on a[a] 3.2.0..<4.0.0, version solving failed.
            """)
    }

    func testIncompatibleToolsVersion5() {
        builder.serve("a", at: "3.2.0", isToolsVersionCompatible: false)
        builder.serve("a", at: "3.2.1", isToolsVersionCompatible: false)
        builder.serve("a", at: "3.2.2", isToolsVersionCompatible: false)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0")), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because every version of a[a] contains incompatible tools version and root depends on a[a] 3.2.0..<4.0.0, version solving failed.
            """)
    }

    func testIncompatibleToolsVersion6() {
        builder.serve("a", at: "3.2.1", isToolsVersionCompatible: false)
        builder.serve("a", at: "3.2.0", with: [
            "a": ["b": (.versionSet(v1Range), .specific(["b"]))],
        ])
        builder.serve("a", at: "3.2.2", isToolsVersionCompatible: false)
        builder.serve("b", at: "1.0.0", isToolsVersionCompatible: false)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0")), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because b[b] 1.0.0 contains incompatible tools version and no versions of b[b] match the requirement 1.0.1..<2.0.0, b[b] >=1.0.0 is forbidden.
            And because a[a] <3.2.1 depends on b[b] 1.0.0..<2.0.0, a[a] <3.2.1 is forbidden.
            And because a[a] >=3.2.1 contains incompatible tools version and root depends on a[a] 3.2.0..<4.0.0, version solving failed.
            """)
    }

    func testConflict4() {
        builder.serve("foo", at: v1, with: [
            "foo": ["shared": (.versionSet(.range("2.0.0"..<"3.0.0")), .specific(["shared"]))],
        ])
        builder.serve("bar", at: v1, with: [
            "bar": ["shared": (.versionSet(.range("2.9.0"..<"4.0.0")), .specific(["shared"]))],
        ])
        builder.serve("shared", at: "2.5.0")
        builder.serve("shared", at: "3.5.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.exact(v1)), .specific(["bar"])),
            "foo": (.versionSet(.exact(v1)), .specific(["foo"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because every version of bar[bar] depends on shared[shared] 2.9.0..<4.0.0 and no versions of shared[shared] match the requirement 2.9.0..<3.0.0, every version of bar[bar] requires shared[shared] 3.0.0..<4.0.0.
            And because every version of foo[foo] depends on shared[shared] 2.0.0..<3.0.0, foo[foo] is incompatible with bar[bar].
            And because root depends on bar[bar] 1.0.0 and root depends on foo[foo] 1.0.0, version solving failed.
            """)
    }

    func testConflict5() {
        builder.serve("a", at: v1, with: [
            "a": ["b": (.versionSet(.exact("1.0.0")), .specific(["b"]))],
        ])
        builder.serve("a", at: "2.0.0", with: [
            "a": ["b": (.versionSet(.exact("2.0.0")), .specific(["b"]))],
        ])
        builder.serve("b", at: "1.0.0", with: [
            "b": ["a": (.versionSet(.exact("2.0.0")), .specific(["a"]))],
        ])
        builder.serve("b", at: "2.0.0", with: [
            "b": ["a": (.versionSet(.exact("1.0.0")), .specific(["a"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "b": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["b"])),
            "a": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(result.errorMsg, """
            because no versions of a[a] match the requirement 3.0.0..<5.0.0 and a[a] <2.0.0 depends on b[b] 1.0.0, a[a] {0.0.0..<2.0.0, 3.0.0..<5.0.0} requires b[b] 1.0.0.
            And because b[b] <2.0.0 depends on a[a] 2.0.0, a[a] {0.0.0..<2.0.0, 3.0.0..<5.0.0} is forbidden.
            because b[b] >=2.0.0 depends on a[a] 1.0.0 and a[a] >=2.0.0 depends on b[b] 2.0.0, a[a] >=2.0.0 is forbidden.
            Thus, a[a] is forbidden.
            And because root depends on a[a] 0.0.0..<5.0.0, version solving failed.
            """)
    }

    func testProductsCannotResolveToDifferentVersions() {
        builder.serve("root", at: .unversioned, with: [
            "root": [
                "intermediate_a": (.versionSet(v1Range), .specific(["Intermediate A"])),
                "intermediate_b": (.versionSet(v1Range), .specific(["Intermediate B"]))
            ]
        ])
        builder.serve("intermediate_a", at: v1, with: [
            "Intermediate A": [
                "transitive": (.versionSet(.exact(v1)), .specific(["Product A"]))
            ]
        ])
        builder.serve("intermediate_b", at: v1, with: [
            "Intermediate B": [
                "transitive": (.versionSet(.exact(v1_1)), .specific(["Product B"]))
            ]
        ])
        builder.serve("transitive", at: v1, with: [
            "Product A": [:],
            "Product B": [:]
        ])
        builder.serve("transitive", at: v1_1, with: [
            "Product A": [:],
            "Product B": [:]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "root": (.unversioned, .everything)
        ])
        let result = resolver.solve(dependencies: dependencies)

        XCTAssertEqual(
            result.errorMsg,
            """
            because every version of intermediate_b[Intermediate B] depends on transitive[Product B] 1.1.0 and transitive[Product B] >=1.1.0 depends on transitive 1.1.0, every version of intermediate_b[Intermediate B] requires transitive 1.1.0.
            And because transitive[Product A] <1.1.0 depends on transitive 1.0.0 and every version of intermediate_a[Intermediate A] depends on transitive[Product A] 1.0.0, intermediate_b[Intermediate B] is incompatible with intermediate_a[Intermediate A].
            And because root depends on intermediate_a[Intermediate A] 1.0.0..<2.0.0 and root depends on intermediate_b[Intermediate B] 1.0.0..<2.0.0, version solving failed.
            """
        )
    }
}

final class PubGrubBacktrackTests: XCTestCase {
    func testBacktrack1() {
        builder.serve("a", at: v1)
        builder.serve("a", at: "2.0.0", with: [
            "a": ["b": (.versionSet(.exact("1.0.0")), .specific(["b"]))],
        ])
        builder.serve("b", at: "1.0.0", with: [
            "b": ["a": (.versionSet(.exact("1.0.0")), .specific(["a"]))],
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"3.0.0")), .specific(["a"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
        ])
    }

    func testBacktrack2() {
        builder.serve("a", at: v1)
        builder.serve("a", at: "2.0.0", with: [
            "a": ["c": (.versionSet(.range("1.0.0"..<"2.0.0")), .specific(["c"]))],
        ])

        builder.serve("b", at: "1.0.0", with: [
            "b": ["c": (.versionSet(.range("2.0.0"..<"3.0.0")), .specific(["c"]))],
        ])
        builder.serve("b", at: "2.0.0", with: [
            "b": ["c": (.versionSet(.range("3.0.0"..<"4.0.0")), .specific(["c"]))],
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0")
        builder.serve("c", at: "3.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"3.0.0")), .specific(["a"])),
            "b": (.versionSet(.range("1.0.0"..<"3.0.0")), .specific(["b"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version("2.0.0")),
            ("c", .version("3.0.0")),
        ])
    }

    func testBacktrack3() {
        builder.serve("a", at: "1.0.0", with: [
            "a": ["x": (.versionSet(.range("1.0.0"..<"5.0.0")), .specific(["x"]))],
        ])
        builder.serve("b", at: "1.0.0", with: [
            "b": ["x": (.versionSet(.range("0.0.0"..<"2.0.0")), .specific(["x"]))],
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0", with: [
            "c": [
                "a": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["a"])),
                "b": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["b"])),
            ]
        ])

        builder.serve("x", at: "0.0.0")
        builder.serve("x", at: "2.0.0")
        builder.serve("x", at: "1.0.0", with: [
            "x": ["y": (.versionSet(.exact(v1)), .specific(["y"]))],
        ])

        builder.serve("y", at: "1.0.0")
        builder.serve("y", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(.range("1.0.0"..<"3.0.0")), .specific(["c"])),
            "y": (.versionSet(.range("2.0.0"..<"3.0.0")), .specific(["y"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("c", .version(v1)),
            ("y", .version("2.0.0")),
        ])
    }

    func testBacktrack4() {
        builder.serve("a", at: "1.0.0", with: [
            "a": ["x": (.versionSet(.range("1.0.0"..<"5.0.0")), .specific(["x"]))],
        ])
        builder.serve("b", at: "1.0.0", with: [
            "b": ["x": (.versionSet(.range("0.0.0"..<"2.0.0")), .specific(["x"]))],
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0", with: [
            "c": [
                "a": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["a"])),
                "b": (.versionSet(.range("0.0.0"..<"5.0.0")), .specific(["b"])),
            ]
        ])

        builder.serve("x", at: "0.0.0")
        builder.serve("x", at: "2.0.0")
        builder.serve("x", at: "1.0.0", with: [
            "x": ["y": (.versionSet(.exact(v1)), .specific(["y"]))],
        ])

        builder.serve("y", at: "1.0.0")
        builder.serve("y", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(.range("1.0.0"..<"3.0.0")), .specific(["c"])),
            "y": (.versionSet(.range("2.0.0"..<"3.0.0")), .specific(["y"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("c", .version(v1)),
            ("y", .version("2.0.0")),
        ])
    }

    func testBacktrack5() {
        builder.serve("foo", at: "1.0.0", with: [
            "foo": ["bar": (.versionSet(.exact("1.0.0")), .specific(["bar"]))],
        ])
        builder.serve("foo", at: "2.0.0", with: [
            "foo": ["bar": (.versionSet(.exact("2.0.0")), .specific(["bar"]))],
        ])
        builder.serve("foo", at: "3.0.0", with: [
            "foo": ["bar": (.versionSet(.exact("3.0.0")), .specific(["bar"]))],
        ])

        builder.serve("bar", at: "1.0.0", with: [
            "bar": ["baz": (.versionSet(.range("0.0.0"..<"3.0.0")), .specific(["baz"]))],
        ])
        builder.serve("bar", at: "2.0.0", with: [
            "bar": ["baz": (.versionSet(.exact("3.0.0")), .specific(["baz"]))],
        ])
        builder.serve("bar", at: "3.0.0", with: [
            "bar": ["baz": (.versionSet(.exact("3.0.0")), .specific(["baz"]))],
        ])

        builder.serve("baz", at: "1.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.range("1.0.0"..<"4.0.0")), .specific(["foo"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("foo", .version(v1)),
            ("bar", .version("1.0.0")),
            ("baz", .version("1.0.0")),
        ])
    }

    func testBacktrack6() {
        builder.serve("a", at: "1.0.0")
        builder.serve("a", at: "2.0.0")
        builder.serve("b", at: "1.0.0", with: [
            "b": ["a": (.versionSet(.exact("1.0.0")), .specific(["a"]))],
        ])
        builder.serve("c", at: "1.0.0", with: [
            "c": ["b": (.versionSet(.range("0.0.0"..<"3.0.0")), .specific(["b"]))],
        ])
        builder.serve("d", at: "1.0.0")
        builder.serve("d", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"4.0.0")), .specific(["a"])),
            "c": (.versionSet(.range("1.0.0"..<"4.0.0")), .specific(["c"])),
            "d": (.versionSet(.range("1.0.0"..<"4.0.0")), .specific(["d"])),
        ])

        let result = resolver.solve(dependencies: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1)),
            ("c", .version(v1)),
            ("d", .version("2.0.0")),
        ])
    }
}

fileprivate extension CheckoutState {
    /// Creates a checkout state with the given version and a mocked revision.
    static func version(_ version: Version) -> CheckoutState {
        CheckoutState(revision: Revision(identifier: "<fake-ident>"), version: version)
    }

    static func branch(_ branch: String, revision: String) -> CheckoutState {
        CheckoutState(revision: Revision(identifier: revision), branch: branch)
    }
}

/// Asserts that the listed packages are present in the bindings with their
/// specified versions.
private func AssertBindings(
    _ bindings: [DependencyResolver.Binding],
    _ packages: [(identity: String, version: BoundVersion)],
    file: StaticString = #file,
    line: UInt = #line
) {
    if bindings.count > packages.count {
        let unexpectedBindings = bindings
            .filter { binding in
                packages.contains(where: { pkg in
                    pkg.0 != binding.container.identity
                })
            }
            .map { $0.container.identity }

        XCTFail("Unexpected binding(s) found for \(unexpectedBindings.joined(separator: ", ")).", file: file, line: line)
    }
    for package in packages {
        guard let binding = bindings.first(where: { $0.container.identity == package.identity }) else {
            XCTFail("No binding found for \(package.identity).", file: file, line: line)
            continue
        }

        if binding.binding != package.version {
            XCTFail("Expected \(package.version) for \(package.identity), found \(binding.binding) instead.", file: file, line: line)
        }
    }
}

/// Asserts that a result succeeded and contains the specified bindings.
private func AssertResult(
    _ result: PubgrubDependencyResolver.Result,
    _ packages: [(identity: String, version: BoundVersion)],
    file: StaticString = #file,
    line: UInt = #line
) {
    switch result {
    case .success(let bindings):
        AssertBindings(bindings, packages, file: file, line: line)
    case .error(let error):
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

/// Asserts that a result failed with specified error.
private func AssertError(
    _ result: PubgrubDependencyResolver.Result,
    _ expectedError: Error,
    file: StaticString = #file,
    line: UInt = #line
) {
    switch result {
    case .success(let bindings):
        let bindingsDesc = bindings.map { "\($0.container)@\($0.binding)" }.joined(separator: ", ")
        XCTFail("Expected unresolvable graph, found bindings instead: \(bindingsDesc)", file: file, line: line)
    case .error(let foundError):
        XCTAssertEqual(String(describing: foundError), String(describing: expectedError), file: file, line: line)
    }
}

public class MockContainer: PackageContainer {
    public typealias Dependency = (container: PackageReference, requirement: PackageRequirement, productFilter: ProductFilter)

    var name: PackageReference
    var manifestName: PackageReference?

    var dependencies: [String: [String: [Dependency]]]

    public var unversionedDeps: [PackageContainerConstraint] = []

    /// Contains the versions for which the dependencies were requested by resolver using getDependencies().
    public var requestedVersions: Set<Version> = []

    public var identifier: PackageReference {
        return name
    }

    /// The list of versions that have incompatible tools version.
    var incompatibleToolsVersions: [Version] = []

    public var _versions: [BoundVersion]

    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        var versions: [Version] = []
        for version in self._versions {
            guard case .version(let v) = version else { continue }
            if isIncluded(v) {
                versions.append(v)
            }
        }
        return AnySequence(versions)
    }

    public var reversedVersions: [Version] {
        var versions: [Version] = []
        for version in self._versions {
            guard case .version(let v) = version else { continue }
            versions.append(v)
        }
        return versions
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        return !incompatibleToolsVersions.contains(version)
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        requestedVersions.insert(version)
        return try getDependencies(at: version.description, productFilter: productFilter)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        guard let revisionDependencies = dependencies[revision] else {
            throw _MockLoadingError.unknownRevision
        }
        var filteredDependencies: [MockContainer.Dependency] = []
        for (product, productDependencies) in revisionDependencies where productFilter.contains(product) {
            filteredDependencies.append(contentsOf: productDependencies)
        }
        return filteredDependencies.map({ value in
            let (name, requirement, filter) = value
            return PackageContainerConstraint(container: name, requirement: requirement, products: filter)
        })
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        // FIXME: This is messy, remove unversionedDeps property.
        if !unversionedDeps.isEmpty {
            return unversionedDeps
        }
        return try getDependencies(at: PackageRequirement.unversioned.description, productFilter: productFilter)
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        if let manifestName = manifestName {
            name = name.with(newName: manifestName.identity)
        }
        return name
    }

    public convenience init(
        name: PackageReference,
        unversionedDependencies: [(package: PackageReference, requirement: PackageRequirement, productFilter: ProductFilter)]
        ) {
        self.init(name: name)
        self.unversionedDeps = unversionedDependencies
            .map { PackageContainerConstraint(container: $0.package, requirement: $0.requirement, products: $0.productFilter) }
    }

    public convenience init(
        name: PackageReference,
        dependenciesByVersion: [Version: [String: [(
            package: PackageReference,
            requirement: VersionSetSpecifier,
            productFilter: ProductFilter
        )]]]) {
        var dependencies: [String: [String: [Dependency]]] = [:]
        for (version, productDependencies) in dependenciesByVersion {
            if dependencies[version.description] == nil {
                dependencies[version.description] = [:]
            }
            for (product, deps) in productDependencies {
                dependencies[version.description, default: [:]][product] = deps.map({
                    ($0.package, .versionSet($0.requirement), $0.productFilter)
                })
            }
        }
        self.init(name: name, dependencies: dependencies)
    }

    public init(
        name: PackageReference,
        dependencies: [String: [String: [Dependency]]] = [:]
        ) {
        self.name = name
        self.dependencies = dependencies
        let versions = dependencies.keys.compactMap(Version.init(string:))
        self._versions = versions
            .sorted()
            .reversed()
            .map(BoundVersion.version)
    }
}

public enum _MockLoadingError: Error {
    case unknownModule
    case unknownRevision
}

public struct MockProvider: PackageContainerProvider {

    public let containers: [MockContainer]
    public let containersByIdentifier: [PackageReference: MockContainer]

    public init(containers: [MockContainer]) {
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
                .failure(_MockLoadingError.unknownModule))
        }
    }
}

struct _MockResolverDelegate: DependencyResolverDelegate {}

class DependencyGraphBuilder {
    private var containers: [String: MockContainer] = [:]
    private var references: [String: PackageReference] = [:]

    func reference(for packageName: String) -> PackageReference {
        if let reference = self.references[packageName] {
            return reference
        }
        let newReference = PackageReference(identity: packageName, path: "/" + packageName)
        self.references[packageName] = newReference
        return newReference
    }

    func create(
        dependencies: OrderedDictionary<String, (PackageRequirement, ProductFilter)>
    ) -> [PackageContainerConstraint] {
        return dependencies.map {
            PackageContainerConstraint(container: reference(for: $0), requirement: $1.0, products: $1.1)
        }
    }

    func serve(
        _ package: String,
        at version: Version,
        isToolsVersionCompatible: Bool = true,
        with dependencies: OrderedDictionary<String, OrderedDictionary<String, (PackageRequirement, ProductFilter)>> = [:]
    ) {
        serve(package, at: .version(version), isToolsVersionCompatible: isToolsVersionCompatible, with: dependencies)
    }

    func serve(
        _ package: String,
        at version: BoundVersion,
        isToolsVersionCompatible: Bool = true,
        with dependencies: OrderedDictionary<String, OrderedDictionary<String, (PackageRequirement, ProductFilter)>> = [:]
    ) {
        let packageReference = reference(for: package)
        let container = self.containers[package] ?? MockContainer(name: packageReference)

        if !isToolsVersionCompatible {
            if case .version(let v) = version {
                container.incompatibleToolsVersions.append(v)
            } else {
                fatalError("Setting incompatible tools version on non-versions is not currently supported")
            }
        }

        container._versions.append(version)
        container._versions = container._versions
            .sorted(by: { lhs, rhs -> Bool in
                guard case .version(let lv) = lhs, case .version(let rv) = rhs else {
                    return true
                }
                return lv < rv
            })
            .reversed()

        if container.dependencies[version.description] == nil {
            container.dependencies[version.description] = [:]
        }
        for (product, filteredDependencies) in dependencies {
            let packageDependencies: [MockContainer.Dependency] = filteredDependencies.map {
                (container: reference(for: $0), requirement: $1.0, products: $1.1)
            }
            container.dependencies[version.description, default: [:]][product] = packageDependencies
        }
        self.containers[package] = container
    }

    /// Creates a pins store with the given pins.
    func create(pinsStore pins: [String: (CheckoutState, ProductFilter)]) -> PinsStore {
        let fs = InMemoryFileSystem()
        let store = try! PinsStore(pinsFile: AbsolutePath("/tmp/Package.resolved"), fileSystem: fs)

        for (package, pin) in pins {
            store.pin(packageRef: reference(for: package), state: pin.0)
        }

        try! store.saveState()
        return store
    }

    func create(log: Bool = false) -> PubgrubDependencyResolver {
        defer {
            self.containers = [:]
            self.references = [:]
        }
        let provider = MockProvider(containers: self.containers.values.map { $0 })
        return PubgrubDependencyResolver(provider, delegate, traceStream: log ? stdoutStream : nil)
    }
}

extension Term: ExpressibleByStringLiteral {
    init(_ value: String) {
        self.init(stringLiteral: value)
    }

    public init(stringLiteral value: String) {
        var value = value

        var isPositive = true
        if value.hasPrefix("¬") {
            value.removeFirst()
            isPositive = false
        }

        var components: [String] = []
        var requirement: PackageRequirement?

        if value.contains("@") {
            components = value.split(separator: "@").map(String.init)
            if components[1].contains(".") {
                requirement = .versionSet(.exact(Version(stringLiteral: components[1])))
            }
        } else if value.contains("^") {
            components = value.split(separator: "^").map(String.init)
            let upperMajor = Int(String(components[1].split(separator: ".").first!))! + 1
            requirement = .versionSet(.range(Version(stringLiteral: components[1])..<Version(stringLiteral: "\(upperMajor).0.0")))
        } else if value.contains("-") {
            components = value.split(separator: "-").map(String.init)
            assert(components.count == 3, "expected `name-lowerBound-upperBound`")
            let (lowerBound, upperBound) = (components[1], components[2])
            requirement = .versionSet(.range(Version(stringLiteral: lowerBound)..<Version(stringLiteral: upperBound)))
        }

        let packageReference = PackageReference(identity: components[0], path: "", name: components[0])

        guard case let .versionSet(vs) = requirement! else {
            fatalError()
        }
        self.init(node: .product(packageReference.name, package: packageReference),
                  requirement: vs,
                  isPositive: isPositive)
    }
}

extension PackageReference: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let ref = PackageReference(identity: value.lowercased(), path: "")
        self = ref
    }

    init(_ name: String) {
        self.init(identity: name, path: "")
    }
}

extension DependencyResolver.Result {
    var errorMsg: String? {
        switch self {
        case .error(let error):
            switch error {
            case let err as PubgrubDependencyResolver.PubgrubError:
                guard case .unresolvable(let msg) = err else {
                    XCTFail("Unexpected result \(self)")
                    return nil
                }
                return msg
            case let error as DependencyResolverError:
                return error.description
            default:
                XCTFail("Unexpected result \(self)")
        }
        default:
            XCTFail("Unexpected result \(self)")
        }
        return nil
    }
}
