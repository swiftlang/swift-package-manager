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
@testable import PackageModel
@testable import PackageGraph
import SourceControl
import SPMTestSupport



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

private let v1: Version = "1.0.0"
private let v1_1: Version = "1.1.0"
private let v1_5: Version = "1.5.0"
private let v2: Version = "2.0.0"
private let v3: Version = "3.0.0"
private let v1Range: VersionSetSpecifier = .range(v1..<v2)
private let v1_5Range: VersionSetSpecifier = .range(v1_5..<v2)
private let v1to3Range: VersionSetSpecifier = .range(v1..<v3)
private let v2Range: VersionSetSpecifier = .range(v2..<v3)

let aRef = PackageReference.localSourceControl(identity: .plain("a"), path: .root)
let bRef = PackageReference.localSourceControl(identity: .plain("b"), path: .root)
let cRef = PackageReference.localSourceControl(identity: .plain("c"), path: .root)

let rootRef = PackageReference.root(identity: PackageIdentity("root"), path: .root)
let rootCause = try! Incompatibility(Term(rootRef, .exact(v1)), root: rootRef)
let _cause = try! Incompatibility("cause@0.0.0", root: rootRef)

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
        let anyA = Term("a", .any)
        XCTAssertNil(Term("a^1.0.0").difference(with: anyA))

        let notEmptyA = Term(not: "a", .empty)
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

    func testIncompatibilityNormalizeTermsOnInit() throws {
        let i1 = try Incompatibility(Term("a^1.0.0"), Term("a^1.5.0"), Term("¬b@1.0.0"), root: rootRef)
        XCTAssertEqual(i1.terms.count, 2)
        let a1 = i1.terms.first { $0.package == "a" }
        let b1 = i1.terms.first { $0.package == "b" }
        XCTAssertEqual(a1?.requirement, v1_5Range)
        XCTAssertEqual(b1?.requirement, .exact(v1))

        let i2 = try Incompatibility(Term("¬a^1.0.0"), Term("a^2.0.0"), root: rootRef)
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
        let a1: Term? = s1._positive.first { $0.key.identity == PackageIdentity("a") }?.value
        XCTAssertEqual(a1?.requirement, v1_5Range)
        let b1: Term? = s1._positive.first { $0.key.identity == PackageIdentity("b") }?.value
        XCTAssertEqual(b1?.requirement, .exact(v2))

        let s2 = PartialSolution(assignments: [
            .derivation("¬a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a2: Term? = s2._positive.first { $0.key.identity == PackageIdentity("a") }?.value
        XCTAssertEqual(a2?.requirement, .range(v1..<v1_5))
    }

    func testSolutionUndecided() {
        var solution = PartialSolution()
        solution.derive("a^1.0.0", cause: rootCause)
        solution.decide("b", at: v2)
        solution.derive("a^1.5.0", cause: rootCause)
        solution.derive("¬c^1.5.0", cause: rootCause)
        solution.derive("d^1.9.0", cause: rootCause)
        solution.derive("d^1.9.9", cause: rootCause)

        let undecided = solution.undecided.sorted{ $0.package.identity < $1.package.identity }
        XCTAssertEqual(undecided, [Term("a^1.5.0"), Term("d^1.9.9")])
    }

    func testSolutionAddAssignments() {
        let root = Term(rootRef, .exact("1.0.0"))
        let a = Term("a@1.0.0")
        let b = Term("b@2.0.0")

        var solution = PartialSolution(assignments: [])
        solution.decide(rootRef, at: v1)
        solution.decide(aRef, at: v1)
        solution.derive(b, cause: _cause)
        XCTAssertEqual(solution.decisionLevel, 1)

        XCTAssertEqual(solution.assignments, [
            .decision(root, decisionLevel: 0),
            .decision(a, decisionLevel: 1),
            .derivation(b, cause: _cause, decisionLevel: 1)
        ])
        XCTAssertEqual(solution.decisions, [
            rootRef: v1,
            aRef: v1,
        ])
    }

    func testSolutionBacktrack() {
        // TODO: This should probably add derivations to cover that logic as well.
        var solution = PartialSolution()
        solution.decide(aRef, at: v1)
        solution.decide(bRef, at: v1)
        solution.decide(cRef, at: v1)

        XCTAssertEqual(solution.decisionLevel, 2)
        solution.backtrack(toDecisionLevel: 1)
        XCTAssertEqual(solution.assignments.count, 2)
        XCTAssertEqual(solution.decisionLevel, 1)
    }

    func testPositiveTerms() {
        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
        ])
        XCTAssertEqual(s1._positive["a"]?.requirement, v1Range)

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0)
        ])
        XCTAssertEqual(s2._positive["a"]?.requirement, v1_5Range)
    }

    func testResolverAddIncompatibility() throws {
        let state = PubgrubDependencyResolver.State(root: rootRef)

        let a = try Incompatibility(Term("a@1.0.0"), root: rootRef)
        state.addIncompatibility(a, at: .topLevel)
        let ab = try Incompatibility(Term("a@1.0.0"), Term("b@2.0.0"), root: rootRef)
        state.addIncompatibility(ab, at: .topLevel)

        XCTAssertEqual(state.incompatibilities, [
            "a": [a, ab],
            "b": [ab],
        ])
    }

    func testUpdatePackageIdentifierAfterResolution() {
        let fooURL = URL(string: "https://example.com/foo")!
        let fooRef = PackageReference.remoteSourceControl(identity: PackageIdentity(url: fooURL), url: fooURL)
        let foo = MockContainer(package: fooRef, dependenciesByVersion: [v1: []])
        foo.manifestName = "bar"

        let provider = MockProvider(containers: [foo])

        let resolver = PubgrubDependencyResolver(provider: provider)
        let deps = builder.create(dependencies: [
            "foo": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: deps)

        switch result {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 1)
            let foo = bindings.first { $0.package.identity == PackageIdentity("foo") }
            XCTAssertEqual(foo?.package.name, "bar")
        }
    }

    func testResolverConflictResolution() throws  {
        let solver1 = PubgrubDependencyResolver(provider: emptyProvider)
        let state1 = PubgrubDependencyResolver.State(root: rootRef)

        let notRoot = try Incompatibility(Term(not: rootRef, .any),
                                      root: rootRef,
                                      cause: .root)
        state1.addIncompatibility(notRoot, at: .topLevel)
        XCTAssertThrowsError(try solver1.resolve(state: state1, conflict: notRoot))
    }

    func testResolverDecisionMaking() throws {
        let solver1 = PubgrubDependencyResolver(provider: emptyProvider)
        let state1 = PubgrubDependencyResolver.State(root: rootRef)

        // No decision can be made if no unsatisfied terms are available.
        XCTAssertNil(try tsc_await { solver1.makeDecision(state: state1, completion: $0) })

        let a = MockContainer(package: aRef, dependenciesByVersion: [
            "0.0.0": [],
            v1: [(package: bRef, requirement: v1Range)]
        ])

        let provider = MockProvider(containers: [a])
        let solver2 = PubgrubDependencyResolver(provider: provider)
        let solution = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])
        let state2 = PubgrubDependencyResolver.State(root: rootRef, solution: solution)

        XCTAssertEqual(state2.incompatibilities.count, 0)

        let decision = try tsc_await { solver2.makeDecision(state: state2, completion: $0) }
        XCTAssertEqual(decision, "a")

        XCTAssertEqual(state2.incompatibilities.count, 2)
        XCTAssertEqual(state2.incompatibilities["a"], [
            try Incompatibility("a^1.0.0", "¬b^1.0.0",
                                root: rootRef,
                                cause: .dependency(package: "a"))
        ])
    }

    func testResolverUnitPropagation() throws {
        let solver1 = PubgrubDependencyResolver(provider: emptyProvider)
        let state1 = PubgrubDependencyResolver.State(root: rootRef)

        // no known incompatibilities should result in no satisfaction checks
        try solver1.propagate(state: state1, package: "root")

        // even if incompatibilities are present
        state1.addIncompatibility(try Incompatibility(Term("a@1.0.0"), root: rootRef), at: .topLevel)
        try solver1.propagate(state: state1, package: "a")
        try solver1.propagate(state: state1, package: "a")
        try solver1.propagate(state: state1, package: "a")

        XCTAssertEqual(state1.solution.assignments.count, 1)

        // FIXME: This leads to fatal error.
        // adding a satisfying term should result in a conflict
        //state1.decide(aRef, at: v1)
        // try solver1.propagate(aRef)

        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        let solver2 = PubgrubDependencyResolver(provider: emptyProvider)
        let state2 = PubgrubDependencyResolver.State(root: rootRef)
        state2.addIncompatibility(try Incompatibility(Term("root", .any),
                                                      Term("¬a@1.0.0"),
                                                      root: rootRef), at: .topLevel)
        state2.decide(rootRef, at: v1)
        XCTAssertEqual(state2.solution.assignments.count, 1)
        try solver2.propagate(state: state2, package: .root(identity: PackageIdentity("root"), path: .root))
        XCTAssertEqual(state2.solution.assignments.count, 2)
    }

    func testSolutionFindSatisfiers() {
        var solution = PartialSolution()
        solution.decide(rootRef, at: v1) // ← previous, but actually nil because this is the root decision
        solution.derive(Term(aRef, .any), cause: _cause) // ← satisfier
        solution.decide(aRef, at: v2)
        solution.derive("b^1.0.0", cause: _cause)

        XCTAssertEqual(try solution.satisfier(for: Term("b^1.0.0")) .term, "b^1.0.0")
        XCTAssertEqual(try solution.satisfier(for: Term("¬a^1.0.0")).term, "a@2.0.0")
        XCTAssertEqual(try solution.satisfier(for: Term("a^2.0.0")).term, "a@2.0.0")
    }

    func testResolutionNoConflicts() {
        builder.serve("a", at: v1, with: ["b": (.versionSet(v1Range))])
        builder.serve("b", at: v1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1))
        ])
    }

    func testResolutionAvoidingConflictResolutionDuringDecisionMaking() {
        builder.serve("a", at: v1)
        builder.serve("a", at: v1_1, with: ["b": (.versionSet(v2Range))])
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
            "b": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

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
        builder.serve("a", at: v2, with: ["b": (.versionSet(v1Range))])
        builder.serve("b", at: v1, with: ["a": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1to3Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .version(v1))
        ])
    }

    func testResolutionConflictResolutionWithAPartialSatisfier() {
        builder.serve("foo", at: v1)
        builder.serve("foo", at: v1_1, with: [
            "left": (.versionSet(v1Range)),
            "right": (.versionSet(v1Range))
        ])
        builder.serve("left", at: v1, with: ["shared": (.versionSet(v1Range))])
        builder.serve("right", at: v1, with: ["shared": (.versionSet(v1Range))])
        builder.serve("shared", at: v1, with: ["target": (.versionSet(v1Range))])
        builder.serve("shared", at: v2)
        builder.serve("target", at: v1)
        builder.serve("target", at: v2)

        // foo 1.1.0 transitively depends on a version of target that's not compatible
        // with root's constraint. This dependency only exists because of left
        // *and* right, choosing only one of these would be fine.

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "target": (.versionSet(v2Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .version(v1)),
            ("target", .version(v2))
        ])
    }

    func testCycle1() {
        builder.serve("foo", at: v1_1, with: ["foo": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .version(v1_1)),
        ])
    }

    func testCycle2() {
        builder.serve("foo", at: v1_1, with: ["bar": (.versionSet(v1Range))])
        builder.serve("bar", at: v1, with: ["baz": (.versionSet(v1Range))])
        builder.serve("baz", at: v1, with: ["bam": (.versionSet(v1Range))])
        builder.serve("bam", at: v1, with: ["baz": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .version(v1_1)),
            ("bar", .version(v1)),
            ("baz", .version(v1)),
            ("bam", .version(v1)),
        ])
    }

    func testLocalPackageCycle() {
        builder.serve("foo", at: .unversioned, with: [
            "bar": (.unversioned),
        ])
        builder.serve("bar", at: .unversioned, with: [
            "baz": (.unversioned),
        ])
        builder.serve("baz", at: .unversioned, with: [
            "foo": (.unversioned),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .unversioned),
            ("baz", .unversioned),
        ])
    }

    func testBranchBasedPackageCycle() {
        builder.serve("foo", at: .revision("develop"), with: [
            "bar": (.revision("develop")),
        ])
        builder.serve("bar", at: .revision("develop"), with: [
            "baz": (.revision("develop")),
        ])
        builder.serve("baz", at: .revision("develop"), with: [
            "foo": (.revision("develop")),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("develop")),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("develop")),
            ("bar", .revision("develop")),
            ("baz", .revision("develop")),
        ])
    }

    func testNonExistentPackage() {
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "package": (.versionSet(.exact(v1))),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertError(result, _MockLoadingError.unknownModule)
    }

    func testUnversioned1() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: v1_5)
        builder.serve("bar", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
            "bar": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1_5))
        ])
    }

    func testUnversioned2() {
        builder.serve("foo", at: .unversioned, with: [
            "bar": (.versionSet(.range(v1..<"1.2.0")))
        ])
        builder.serve("bar", at: v1)
        builder.serve("bar", at: v1_1)
        builder.serve("bar", at: v1_5)
        builder.serve("bar", at: v2)

        let resolver = builder.create()

        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
            "bar": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1_1))
        ])
    }

    func testUnversioned3() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: v1, with: [
            "foo": (.versionSet(.exact(v1)))
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
            "bar": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .version(v1))
        ])
    }

    func testUnversioned4() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: .revision("master"), with: [
            "foo": (.versionSet(v1Range))
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
            "bar": (.revision("master"))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .revision("master"))
        ])
    }

    func testUnversioned5() {
        builder.serve("foo", at: .unversioned)
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: .revision("master"), with: [
            "foo": (.revision("master"))
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.unversioned),
            "bar": (.revision("master"))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .unversioned),
            ("bar", .revision("master"))
        ])
    }

    func testUnversioned7() {
        builder.serve("local", at: .unversioned, with: [
            "remote": (.unversioned)
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "local": (.unversioned),
            "remote": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("remote", .unversioned),
            ("local", .unversioned)
        ])
    }

    func testUnversioned8() {
        builder.serve("entry", at: .unversioned, with: [
            "remote": (.versionSet(v1Range)),
            "local": (.unversioned),
        ])
        builder.serve("local", at: .unversioned, with: [
            "remote": (.unversioned)
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "entry": (.unversioned),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("entry", .unversioned),
            ("local", .unversioned),
            ("remote", .unversioned),
        ])
    }

    func testUnversioned9() {
        builder.serve("entry", at: .unversioned, with: [
            "local": (.unversioned),
            "remote": (.versionSet(v1Range)),
        ])
        builder.serve("local", at: .unversioned, with: [
            "remote": (.unversioned)
        ])
        builder.serve("remote", at: .unversioned)
        builder.serve("remote", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "entry": (.unversioned),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("entry", .unversioned),
            ("local", .unversioned),
            ("remote", .unversioned),
        ])
    }

    func testResolutionWithSimpleBranchBasedDependency() {
        builder.serve("foo", at: .revision("master"), with: ["bar": (.versionSet(v1Range))])
        builder.serve("bar", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master")),
            "bar": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithSimpleBranchBasedDependency2() {
        builder.serve("foo", at: .revision("master"), with: ["bar": (.versionSet(v1Range))])
        builder.serve("bar", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency() {
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: v1, with: ["foo": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master")),
            "bar": (.versionSet(.exact(v1))),

        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency2() {
        builder.serve("foo", at: .revision("master"))
        builder.serve("bar", at: v1, with: ["foo": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.exact(v1))),
            "foo": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .version(v1))
        ])
    }

    func testResolutionWithOverridingBranchBasedDependency3() {
        builder.serve("foo", at: .revision("master"), with: ["bar": (.revision("master"))])

        builder.serve("bar", at: .revision("master"))
        builder.serve("bar", at: v1)

        builder.serve("baz", at: .revision("master"), with: ["bar": (.versionSet(v1Range))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master")),
            "baz": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

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
            "foo": (.revision("master"))
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertError(result, _MockLoadingError.unknownRevision)
    }

    func testResolutionWithRevisionConflict() {
        builder.serve("foo", at: .revision("master"), with: ["bar": (.revision("master"))])
        builder.serve("bar", at: .version(v1))
        builder.serve("bar", at: .revision("master"))

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(v1Range)),
            "foo": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .revision("master")),
            ("bar", .revision("master")),
        ])
    }

    func testBranchOverriding3() {
        builder.serve("swift-nio", at: v1)
        builder.serve("swift-nio", at: .revision("master"))
        builder.serve("swift-nio-ssl", at: .revision("master"), with: [
            "swift-nio": (.versionSet(v2Range)),
        ])
        builder.serve("foo", at: "1.0.0", with: [
            "swift-nio": (.versionSet(v1Range)),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "swift-nio": (.revision("master")),
            "swift-nio-ssl": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

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
            "swift-nio": (.versionSet(v2Range)),
        ])
        builder.serve("nio-postgres", at: .revision("master"), with: [
            "swift-nio": (.revision("master")),
            "swift-nio-ssl": (.revision("master")),
        ])
        builder.serve("http-client", at: v1, with: [
            "swift-nio": (.versionSet(v1Range)),
            "boring-ssl": (.versionSet(v1Range)),
        ])
        builder.serve("boring-ssl", at: v1, with: [
            "swift-nio": (.versionSet(v1Range)),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "nio-postgres": (.revision("master")),
            "http-client": (.versionSet(v1Range)),
            "boring-ssl": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

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
            "bar": (.revision("master"))
        ])
        builder.serve("foo", at: v1)
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .version(v1)),
        ])
    }

    func testTrivialPinStore() throws {
        builder.serve("a", at: v1, with: ["b": (.versionSet(v1Range))])
        builder.serve("a", at: v1_1)
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("b", at: v2)

        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
        ])

        let pinsStore = builder.create(pinsStore: [
            "a": (.version(v1)),
            "b": (.version(v1)),
        ])

        let resolver = builder.create(pinsMap: pinsStore.pinsMap)
        let result = try resolver.solve(root: rootRef, constraints: dependencies)

        // Since a was pinned, we shouldn't have computed bounds for its incomaptibilities.
        let aIncompat = result.state.positiveIncompatibilities(for: builder.reference(for: "a"))![0]
        XCTAssertEqual(aIncompat.terms[0].requirement, .exact("1.0.0"))

        AssertResult(Result.success(result.bindings), [
            ("a", .version(v1)),
            ("b", .version(v1))
        ])
    }

    func testPartialPins() {
        // This checks that we can drop pins that are not valid anymore but still keep the ones
        // which fit the constraints.
        builder.serve("a", at: v1, with: ["b": (.versionSet(v1Range))])
        builder.serve("a", at: v1_1)
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("c", at: v1, with: ["b": (.versionSet(.range(v1_1..<v2)))])

        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(v1Range)),
            "a": (.versionSet(v1Range)),
        ])

        // Here b is pinned to v1 but its requirement is now 1.1.0..<2.0.0 in the graph
        // due to addition of a new dependency.
        let pinsStore = builder.create(pinsStore: [
            "a": (.version(v1)),
            "b": (.version(v1)),
        ])

        let resolver = builder.create(pinsMap: pinsStore.pinsMap)
        let result = resolver.solve(constraints: dependencies)

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

        let dependencies = builder.create(dependencies: [
            "a": (.revision("develop")),
            "b": (.revision("master")),
        ])

        let pinsStore = builder.create(pinsStore: [
            "a": (.branch("develop", revision: "develop-sha-1")),
            "b": (.branch("master", revision: "master-sha-2")),
        ])

        let resolver = builder.create(pinsMap: pinsStore.pinsMap)
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .revision("develop-sha-1", branch: "develop")),
            ("b", .revision("master-sha-2", branch: "master")),
        ])
    }

    func testIncompatibleToolsVersion2() {
        builder.serve("a", at: v1_1, toolsVersion: ToolsVersion.v5)
        builder.serve("a", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
        ])

        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
        ])
    }

    /* // FIXME: tomer
    func testUnreachableProductsSkipped() throws {
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        #else
        try XCTSkipIf(true)
        #endif

        builder.serve("root", at: .unversioned, with: [
            "immediate": (.versionSet(v1Range))
        ])
        builder.serve("immediate", at: v1, with: [
            "ImmediateUsed": ["transitive": (.versionSet(v1Range))],
            "ImmediateUnused": [
                "transitive": (.versionSet(v1Range)),
                "nonexistent": (.versionSet(v1Range))
            ]
        ])
        builder.serve("transitive", at: v1, with: [
            "TransitiveUsed": [:],
            "TransitiveUnused": [
                "nonexistent": (.versionSet(v1Range))
            ]
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "root": (.unversioned)
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("root", .unversioned),
            ("immediate", .version(v1)),
            ("transitive", .version(v1))
        ])
    }*/

    func testDelegate() {
        class TestDelegate: DependencyResolverDelegate {
            var events = [String]()
            let lock = Lock()

            func willResolve(term: Term) {
                self.lock.withLock {
                    self.events.append("willResolve '\(term.package.identity)'")
                }
            }

            func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
                self.lock.withLock {
                    self.events.append("didResolve '\(term.package.identity)' at '\(version)'")
                }
            }

            func derived(term: Term) {}

            func conflict(conflict: Incompatibility) {}

            func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {}

            func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {}

            func failedToResolve(incompatibility: Incompatibility) {}

            func solved(result: [DependencyResolver.Binding]) {
                let decisions = result.sorted(by: { $0.package.identity < $1.package.identity }).map { "'\($0.package.identity)' at '\($0.binding)'" }
                self.lock.withLock {
                    self.events.append("solved: \(decisions.joined(separator: ", "))")
                }
            }
        }

        builder.serve("foo", at: "1.0.0")
        builder.serve("foo", at: "1.1.0")
        builder.serve("foo", at: "2.0.0")
        builder.serve("foo", at: "2.0.1")

        builder.serve("bar", at: "1.0.0")
        builder.serve("bar", at: "1.1.0")
        builder.serve("bar", at: "2.0.0")
        builder.serve("bar", at: "2.0.1")

        let delegate = TestDelegate()
        let resolver = builder.create(delegate: delegate)
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "bar": (.versionSet(v2Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("foo", .version("1.1.0")),
            ("bar", .version("2.0.1")),
        ])

        XCTAssertMatch(delegate.events, ["willResolve 'foo'"])
        XCTAssertMatch(delegate.events, ["didResolve 'foo' at '1.1.0'"])
        XCTAssertMatch(delegate.events, ["willResolve 'bar'"])
        XCTAssertMatch(delegate.events, ["didResolve 'bar' at '2.0.1'"])
        XCTAssertMatch(delegate.events, ["solved: 'bar' at '2.0.1', 'foo' at '1.1.0'"])
    }
}

final class PubGrubTestsBasicGraphs: XCTestCase {
    func testSimple1() {
        builder.serve("a", at: v1, with: [
            "aa": (.versionSet(.exact("1.0.0"))),
            "ab": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("aa", at: v1)
        builder.serve("ab", at: v1)
        builder.serve("b", at: v1, with: [
            "ba": (.versionSet(.exact("1.0.0"))),
            "bb": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("ba", at: v1)
        builder.serve("bb", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.exact("1.0.0"))),
            "b": (.versionSet(.exact("1.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)
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
            "shared": (.versionSet(.range("2.0.0"..<"4.0.0"))),
        ])
        builder.serve("b", at: v1, with: [
            "shared": (.versionSet(.range("3.0.0"..<"5.0.0"))),
        ])
        builder.serve("shared", at: "2.0.0")
        builder.serve("shared", at: "3.0.0")
        builder.serve("shared", at: "3.6.9")
        builder.serve("shared", at: "4.0.0")
        builder.serve("shared", at: "5.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.exact("1.0.0"))),
            "b": (.versionSet(.exact("1.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)
        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1)),
            ("shared", .version("3.6.9")),
        ])
    }

    func testSharedDependency2() {
        builder.serve("foo", at: "1.0.0")
        builder.serve("foo", at: "1.0.1", with: [
            "bang": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("foo", at: "1.0.2", with: [
            "whoop": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("foo", at: "1.0.3", with: [
            "zoop": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("bar", at: "1.0.0", with: [
            "foo": (.versionSet(.range("0.0.0"..<"1.0.2"))),
        ])
        builder.serve("bang", at: "1.0.0")
        builder.serve("whoop", at: "1.0.0")
        builder.serve("zoop", at: "1.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.range("0.0.0"..<"1.0.3"))),
            "bar": (.versionSet(.exact("1.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)
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
            "baz": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("baz", at: "1.0.0", with: [
            "foo": (.versionSet(.exact("2.0.0"))),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.range("0.0.0"..<"5.0.0"))),
            "foo": (.versionSet(.exact("1.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)
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
            "foopkg": (.versionSet(v2Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because no versions of 'foopkg' match the requirement 2.0.0..<3.0.0 and root depends on 'foopkg' 2.0.0..<3.0.0.
            """)
    }

    func testResolutionNonExistentVersion() {
        builder.serve("package", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "package": (.versionSet(.exact(v1)))
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because no versions of 'package' match the requirement 1.0.0 and root depends on 'package' 1.0.0.
            """)
    }

    func testResolutionLinearErrorReporting() {
        builder.serve("foo", at: v1, with: ["bar": (.versionSet(v2Range))])
        builder.serve("bar", at: v2, with: ["baz": (.versionSet(.range("3.0.0"..<"4.0.0")))])
        builder.serve("baz", at: v1)
        builder.serve("baz", at: "3.0.0")

        // root transitively depends on a version of baz that's not compatible
        // with root's constraint.

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "baz": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'foo' 1.0.0..<2.0.0 and root depends on 'baz' 1.0.0..<2.0.0.
            'foo' practically depends on 'baz' 3.0.0..<4.0.0 because 'foo' depends on 'bar' 2.0.0..<3.0.0 and 'bar' depends on 'baz' 3.0.0..<4.0.0.
            """)
    }

    func testResolutionBranchingErrorReporting() {
        builder.serve("foo", at: v1, with: [
            "a": (.versionSet(v1Range)),
            "b": (.versionSet(v1Range))
        ])
        builder.serve("foo", at: v1_1, with: [
            "x": (.versionSet(v1Range)),
            "y": (.versionSet(v1Range))
        ])
        builder.serve("a", at: v1, with: ["b": (.versionSet(v2Range))])
        builder.serve("b", at: v1)
        builder.serve("b", at: v2)
        builder.serve("x", at: v1, with: ["y": (.versionSet(v2Range))])
        builder.serve("y", at: v1)
        builder.serve("y", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
          Dependencies could not be resolved because root depends on 'foo' 1.0.0..<2.0.0.
          'foo' cannot be used because 'foo' < 1.1.0 cannot be used (1).
          'foo' >= 1.1.0 cannot be used because 'foo' >= 1.1.0 depends on 'y' 1.0.0..<2.0.0.
          'foo' >= 1.1.0 practically depends on 'y' 2.0.0..<3.0.0 because 'x' depends on 'y' 2.0.0..<3.0.0 and 'foo' >= 1.1.0 depends on 'x' 1.0.0..<2.0.0.
          'foo' < 1.1.0 practically depends on 'b' 2.0.0..<3.0.0 because 'a' depends on 'b' 2.0.0..<3.0.0 and 'foo' < 1.1.0 depends on 'a' 1.0.0..<2.0.0.
             (1) As a result, 'foo' < 1.1.0 cannot be used because 'foo' < 1.1.0 depends on 'b' 1.0.0..<2.0.0.
        """)
    }

    func testConflict1() {
        builder.serve("foo", at: v1, with: ["config": (.versionSet(v1Range))])
        builder.serve("bar", at: v1, with: ["config": (.versionSet(v2Range))])
        builder.serve("config", at: v1)
        builder.serve("config", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "bar": (.versionSet(v1Range))
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'foo' 1.0.0..<2.0.0 and root depends on 'bar' 1.0.0..<2.0.0.
            'bar' is incompatible with 'foo' because 'bar' depends on 'config' 2.0.0..<3.0.0 and 'foo' depends on 'config' 1.0.0..<2.0.0.
            """)
    }

    func testConflict2() {
        func addDeps() {
            builder.serve("foo", at: v1, with: ["config": (.versionSet(v1Range))])
            builder.serve("config", at: v1)
            builder.serve("config", at: v2)
        }

        let dependencies1 = builder.create(dependencies: [
            "config": (.versionSet(v2Range)),
            "foo": (.versionSet(v1Range)),
        ])
        addDeps()
        let resolver1 = builder.create()
        let result1 = resolver1.solve(constraints: dependencies1)

        XCTAssertEqual(result1.errorMsg, """
            Dependencies could not be resolved because root depends on 'foo' 1.0.0..<2.0.0.
            'foo' cannot be used because 'foo' depends on 'config' 1.0.0..<2.0.0 and root depends on 'config' 2.0.0..<3.0.0.
            """)

        let dependencies2 = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
            "config": (.versionSet(v2Range)),
        ])
        addDeps()
        let resolver2 = builder.create()
        let result2 = resolver2.solve(constraints: dependencies2)

        XCTAssertEqual(result2.errorMsg, """
            Dependencies could not be resolved because root depends on 'config' 2.0.0..<3.0.0.
            'config' 1.0.0..<2.0.0 is required because 'foo' depends on 'config' 1.0.0..<2.0.0 and root depends on 'foo' 1.0.0..<2.0.0.
            """)
    }

    func testConflict3() {
        builder.serve("foo", at: v1, with: ["config": (.versionSet(v1Range))])
        builder.serve("config", at: v1)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "config": (.versionSet(v2Range)),
            "foo": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because no versions of 'config' match the requirement 2.0.0..<3.0.0 and root depends on 'config' 2.0.0..<3.0.0.
            """)
    }

    func testUnversioned6() {
        builder.serve("foo", at: .unversioned)
        builder.serve("bar", at: .revision("master"), with: [
            "foo": (.unversioned)
        ])

        let resolver = builder.create()

        let dependencies = builder.create(dependencies: [
            "bar": (.revision("master"))
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, "package 'bar' is required using a revision-based requirement and it depends on local package 'foo', which is not supported")
    }

    func testResolutionWithOverridingBranchBasedDependency4() {
        builder.serve("foo", at: .revision("master"), with: ["bar": (.revision("master"))])

        builder.serve("bar", at: .revision("master"))
        builder.serve("bar", at: v1)

        builder.serve("baz", at: .revision("master"), with: ["bar": (.revision("develop"))])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.revision("master")),
            "baz": (.revision("master")),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, "bar is required using two different revision-based requirements (master and develop), which is not supported")
    }

    func testNonVersionDependencyInVersionDependency1() {
        builder.serve("foo", at: v1_1, with: [
            "bar": (.revision("master"))
        ])
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(v1Range)),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'foo' 1.0.0..<2.0.0.
            'foo' cannot be used because no versions of 'foo' match the requirement {1.0.0..<1.1.0, 1.1.1..<2.0.0} and package 'foo' is required using a stable-version but 'foo' depends on an unstable-version package 'bar'.
            """)
    }

    func testNonVersionDependencyInVersionDependency3() {
        builder.serve("foo", at: v1, with: [
            "bar": (.unversioned)
        ])
        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.exact(v1))),
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because package 'foo' is required using a stable-version but 'foo' depends on an unstable-version package 'bar' and root depends on 'foo' 1.0.0.
            """)
    }

    func testIncompatibleToolsVersion1() {
        builder.serve("a", at: v1, toolsVersion: .v5)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'a' 1.0.0..<2.0.0.
            'a' >= 1.0.0 cannot be used because no versions of 'a' match the requirement 1.0.1..<2.0.0 and 'a' 1.0.0 contains incompatible tools version (\(ToolsVersion.v5)).
            """)
    }

    func testIncompatibleToolsVersion3() {
        builder.serve("a", at: v1_1, with: [
            "b": (.versionSet(v1Range))
        ])
        builder.serve("a", at: v1, toolsVersion: .v4)

        builder.serve("b", at: v1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(v1Range)),
            "b": (.versionSet(v2Range)),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'a' 1.0.0..<2.0.0 and root depends on 'b' 2.0.0..<3.0.0.
            'a' >= 1.0.0 practically depends on 'b' 1.0.0..<2.0.0 because 'a' >= 1.1.0 depends on 'b' 1.0.0..<2.0.0.
            'a' 1.0.0..<1.1.0 cannot be used because no versions of 'a' match the requirement 1.0.1..<1.1.0 and 'a' 1.0.0 contains incompatible tools version (\(ToolsVersion.v4)).
            """)
    }

    func testIncompatibleToolsVersion4() {
        builder.serve("a", at: "3.2.1", toolsVersion: .v3)
        builder.serve("a", at: "3.2.2", toolsVersion: .v4)
        builder.serve("a", at: "3.2.3", toolsVersion: .v3)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because 'a' contains incompatible tools version (\(ToolsVersion.v3)) and root depends on 'a' 3.2.0..<4.0.0.
            """)
    }

    func testIncompatibleToolsVersion5() {
        builder.serve("a", at: "3.2.0", toolsVersion: .v3)
        builder.serve("a", at: "3.2.1", toolsVersion: .v4)
        builder.serve("a", at: "3.2.2", toolsVersion: .v5)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because 'a' contains incompatible tools version (\(ToolsVersion.v5)) and root depends on 'a' 3.2.0..<4.0.0.
            """)
    }

    func testIncompatibleToolsVersion6() {
        builder.serve("a", at: "3.2.1", toolsVersion: .v5)
        builder.serve("a", at: "3.2.0", with: [
            "b": (.versionSet(v1Range)),
        ])
        builder.serve("a", at: "3.2.2", toolsVersion: .v4)
        builder.serve("b", at: "1.0.0", toolsVersion: .v3)

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("3.2.0"..<"4.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because 'a' >= 3.2.1 contains incompatible tools version (\(ToolsVersion.v4)) and root depends on 'a' 3.2.0..<4.0.0.
            'a' < 3.2.1 cannot be used because 'a' < 3.2.1 depends on 'b' 1.0.0..<2.0.0.
            'b' >= 1.0.0 cannot be used because no versions of 'b' match the requirement 1.0.1..<2.0.0 and 'b' 1.0.0 contains incompatible tools version (\(ToolsVersion.v3)).
            """)
    }

    func testConflict4() {
        builder.serve("foo", at: v1, with: [
            "shared": (.versionSet(.range("2.0.0"..<"3.0.0"))),
        ])
        builder.serve("bar", at: v1, with: [
            "shared": (.versionSet(.range("2.9.0"..<"4.0.0"))),
        ])
        builder.serve("shared", at: "2.5.0")
        builder.serve("shared", at: "3.5.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "bar": (.versionSet(.exact(v1))),
            "foo": (.versionSet(.exact(v1))),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'bar' 1.0.0 and root depends on 'foo' 1.0.0.
            'foo' is incompatible with 'bar' because 'foo' depends on 'shared' 2.0.0..<3.0.0.
            'bar' practically depends on 'shared' 3.0.0..<4.0.0 because 'bar' depends on 'shared' 2.9.0..<4.0.0 and no versions of 'shared' match the requirement 2.9.0..<3.0.0.
            """)
    }

    func testConflict5() {
        builder.serve("a", at: v1, with: [
            "b": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("a", at: "2.0.0", with: [
            "b": (.versionSet(.exact("2.0.0"))),
        ])
        builder.serve("b", at: "1.0.0", with: [
            "a": (.versionSet(.exact("2.0.0"))),
        ])
        builder.serve("b", at: "2.0.0", with: [
            "a": (.versionSet(.exact("1.0.0"))),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "b": (.versionSet(.range("0.0.0"..<"5.0.0"))),
            "a": (.versionSet(.range("0.0.0"..<"5.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(result.errorMsg, """
            Dependencies could not be resolved because root depends on 'a' 0.0.0..<5.0.0.
            'a' cannot be used.
            'a' >= 2.0.0 cannot be used because 'b' >= 2.0.0 depends on 'a' 1.0.0 and 'a' >= 2.0.0 depends on 'b' 2.0.0.
            'a' {0.0.0..<2.0.0, 3.0.0..<5.0.0} cannot be used because 'b' < 2.0.0 depends on 'a' 2.0.0.
            'a' {0.0.0..<2.0.0, 3.0.0..<5.0.0} practically depends on 'b' 1.0.0 because no versions of 'a' match the requirement 3.0.0..<5.0.0 and 'a' < 2.0.0 depends on 'b' 1.0.0.
            """)
    }

    /*
    func testProductsCannotResolveToDifferentVersions() {
        builder.serve("root", at: .unversioned, with: [
            "intermediate_a": (.versionSet(v1Range)),
            "intermediate_b": (.versionSet(v1Range))
        ])
        builder.serve("intermediate_a", at: v1, with: [
            "transitive": (.versionSet(.exact(v1)))
        ])
        builder.serve("intermediate_b", at: v1, with: [
            "transitive": (.versionSet(.exact(v1_1)))
        ])
        builder.serve("transitive", at: v1, with: [:])
        builder.serve("transitive", at: v1_1, with: [:])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "root": (.unversioned)
        ])
        let result = resolver.solve(constraints: dependencies)

        XCTAssertEqual(
            result.errorMsg,
            """
            Dependencies could not be resolved because root depends on 'intermediate_a' 1.0.0..<2.0.0 and root depends on 'intermediate_b' 1.0.0..<2.0.0.
            'intermediate_b' is incompatible with 'intermediate_a' because 'transitive' < 1.1.0 depends on 'transitive' 1.0.0 and 'intermediate_a' depends on 'transitive' 1.0.0.
            'intermediate_b' practically depends on 'transitive' 1.1.0 because 'intermediate_b' depends on 'transitive' 1.1.0 and 'transitive' >= 1.1.0 depends on 'transitive' 1.1.0.
            """
        )
    }*/
}

final class PubGrubBacktrackTests: XCTestCase {
    func testBacktrack1() {
        builder.serve("a", at: v1)
        builder.serve("a", at: "2.0.0", with: [
            "b": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("b", at: "1.0.0", with: [
            "a": (.versionSet(.exact("1.0.0"))),
        ])

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"3.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
        ])
    }

    func testBacktrack2() {
        builder.serve("a", at: v1)
        builder.serve("a", at: "2.0.0", with: [
            "c": (.versionSet(.range("1.0.0"..<"2.0.0"))),
        ])

        builder.serve("b", at: "1.0.0", with: [
            "c": (.versionSet(.range("2.0.0"..<"3.0.0"))),
        ])
        builder.serve("b", at: "2.0.0", with: [
            "c": (.versionSet(.range("3.0.0"..<"4.0.0"))),
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0")
        builder.serve("c", at: "3.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"3.0.0"))),
            "b": (.versionSet(.range("1.0.0"..<"3.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version("2.0.0")),
            ("c", .version("3.0.0")),
        ])
    }

    func testBacktrack3() {
        builder.serve("a", at: "1.0.0", with: [
            "x": (.versionSet(.range("1.0.0"..<"5.0.0"))),
        ])
        builder.serve("b", at: "1.0.0", with: [
            "x": (.versionSet(.range("0.0.0"..<"2.0.0"))),
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0", with: [
            "a": (.versionSet(.range("0.0.0"..<"5.0.0"))),
            "b": (.versionSet(.range("0.0.0"..<"5.0.0"))),
        ])

        builder.serve("x", at: "0.0.0")
        builder.serve("x", at: "2.0.0")
        builder.serve("x", at: "1.0.0", with: [
            "y": (.versionSet(.exact(v1))),
        ])

        builder.serve("y", at: "1.0.0")
        builder.serve("y", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(.range("1.0.0"..<"3.0.0"))),
            "y": (.versionSet(.range("2.0.0"..<"3.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("c", .version(v1)),
            ("y", .version("2.0.0")),
        ])
    }

    func testBacktrack4() {
        builder.serve("a", at: "1.0.0", with: [
            "x": (.versionSet(.range("1.0.0"..<"5.0.0"))),
        ])
        builder.serve("b", at: "1.0.0", with: [
            "x": (.versionSet(.range("0.0.0"..<"2.0.0"))),
        ])

        builder.serve("c", at: "1.0.0")
        builder.serve("c", at: "2.0.0", with: [
            "a": (.versionSet(.range("0.0.0"..<"5.0.0"))),
            "b": (.versionSet(.range("0.0.0"..<"5.0.0"))),
        ])

        builder.serve("x", at: "0.0.0")
        builder.serve("x", at: "2.0.0")
        builder.serve("x", at: "1.0.0", with: [
            "y": (.versionSet(.exact(v1))),
        ])

        builder.serve("y", at: "1.0.0")
        builder.serve("y", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "c": (.versionSet(.range("1.0.0"..<"3.0.0"))),
            "y": (.versionSet(.range("2.0.0"..<"3.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

        AssertResult(result, [
            ("c", .version(v1)),
            ("y", .version("2.0.0")),
        ])
    }

    func testBacktrack5() {
        builder.serve("foo", at: "1.0.0", with: [
            "bar": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("foo", at: "2.0.0", with: [
            "bar": (.versionSet(.exact("2.0.0"))),
        ])
        builder.serve("foo", at: "3.0.0", with: [
            "bar": (.versionSet(.exact("3.0.0"))),
        ])

        builder.serve("bar", at: "1.0.0", with: [
            "baz": (.versionSet(.range("0.0.0"..<"3.0.0"))),
        ])
        builder.serve("bar", at: "2.0.0", with: [
            "baz": (.versionSet(.exact("3.0.0"))),
        ])
        builder.serve("bar", at: "3.0.0", with: [
            "baz": (.versionSet(.exact("3.0.0"))),
        ])

        builder.serve("baz", at: "1.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "foo": (.versionSet(.range("1.0.0"..<"4.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

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
            "a": (.versionSet(.exact("1.0.0"))),
        ])
        builder.serve("c", at: "1.0.0", with: [
            "b": (.versionSet(.range("0.0.0"..<"3.0.0"))),
        ])
        builder.serve("d", at: "1.0.0")
        builder.serve("d", at: "2.0.0")

        let resolver = builder.create()
        let dependencies = builder.create(dependencies: [
            "a": (.versionSet(.range("1.0.0"..<"4.0.0"))),
            "c": (.versionSet(.range("1.0.0"..<"4.0.0"))),
            "d": (.versionSet(.range("1.0.0"..<"4.0.0"))),
        ])

        let result = resolver.solve(constraints: dependencies)

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
        .version(version, revision: Revision(identifier: "<fake-ident>"))
    }

    static func branch(_ branch: String, revision: String) -> CheckoutState {
        .branch(name: branch, revision: Revision(identifier: revision))
    }
}

/// Asserts that the listed packages are present in the bindings with their
/// specified versions.
private func AssertBindings(
    _ bindings: [DependencyResolver.Binding],
    _ packages: [(identity: PackageIdentity, version: BoundVersion)],
    file: StaticString = #file,
    line: UInt = #line
) {
    if bindings.count > packages.count {
        let unexpectedBindings = bindings
            .filter { binding in
                packages.contains(where: { pkg in
                    pkg.identity != binding.package.identity
                })
            }
            .map { $0.package.identity }

        XCTFail("Unexpected binding(s) found for \(unexpectedBindings.map { $0.description }.joined(separator: ", ")).", file: file, line: line)
    }
    for package in packages {
        guard let binding = bindings.first(where: { $0.package.identity == package.identity }) else {
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
    _ result: Result<[DependencyResolver.Binding], Error>,
    _ packages: [(identifier: String, version: BoundVersion)],
    file: StaticString = #file,
    line: UInt = #line
) {
    switch result {
    case .success(let bindings):
        AssertBindings(bindings, packages.map { (PackageIdentity($0.identifier), $0.version) }, file: file, line: line)
    case .failure(let error):
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

/// Asserts that a result failed with specified error.
private func AssertError(
    _ result: Result<[DependencyResolver.Binding], Error>,
    _ expectedError: Error,
    file: StaticString = #file,
    line: UInt = #line
) {
    switch result {
    case .success(let bindings):
        let bindingsDesc = bindings.map { "\($0.package)@\($0.binding)" }.joined(separator: ", ")
        XCTFail("Expected unresolvable graph, found bindings instead: \(bindingsDesc)", file: file, line: line)
    case .failure(let foundError):
        XCTAssertEqual(String(describing: foundError), String(describing: expectedError), file: file, line: line)
    }
}

// FIXME: this is not thread-safe
public class MockContainer: PackageContainer {
    public typealias Dependency = (container: PackageReference, requirement: PackageRequirement)

    public var package: PackageReference
    var manifestName: PackageReference?

    var dependencies: [String: [Dependency]]

    public var unversionedDeps: [PackageContainerConstraint] = []

    /// The list of versions that have incompatible tools version.
    var toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion
    var versionsToolsVersions = [Version: ToolsVersion]()

    private var _versions: [BoundVersion]

    // TODO: this does not actually do anything with the tools-version
    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        var versions: [Version] = []
        for version in self._versions.reversed() {
            guard case .version(let v) = version else { continue }
            versions.append(v)
        }
        return versions
    }

    public func versionsAscending() throws ->  [Version] {
        var versions: [Version] = []
        for version in self._versions {
            guard case .version(let v) = version else { continue }
            versions.append(v)
        }
        return versions
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        // this checks for *exact* version match which is good enough for our current tests
        if let toolsVersion = try? self.toolsVersion(for: version) {
            return self.toolsVersion == toolsVersion
        }

        return (try? self.toolsVersionsAppropriateVersionsDescending().contains(version)) ?? false
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        struct NotFound: Error {}

        guard let version = versionsToolsVersions[version] else {
            throw NotFound()
        }
        return version
    }

    public func getDependencies(at version: Version) throws -> [PackageContainerConstraint] {
        return try getDependencies(at: version.description)
    }

    public func getDependencies(at revision: String) throws -> [PackageContainerConstraint] {
        guard let revisionDependencies = dependencies[revision] else {
            throw _MockLoadingError.unknownRevision
        }
        return revisionDependencies.map{ value in
            let (package, requirement) = value
            return PackageContainerConstraint(package: package, requirement: requirement)
        }
    }

    public func getUnversionedDependencies() throws -> [PackageContainerConstraint] {
        // FIXME: This is messy, remove unversionedDeps property.
        if !unversionedDeps.isEmpty {
            return unversionedDeps
        }
        return try getDependencies(at: PackageRequirement.unversioned.description)
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        if let manifestName = manifestName {
            self.package = self.package.with(newName: manifestName.identity.description)
        }
        return self.package
    }

    func appendVersion(_ version: BoundVersion) {
        self._versions.append(version)
        self._versions = self._versions
            .sorted(by: { lhs, rhs -> Bool in
                guard case .version(let lv) = lhs, case .version(let rv) = rhs else {
                    return true
                }
                return lv < rv
            })
    }

    public convenience init(
        package: PackageReference,
        unversionedDependencies: [(package: PackageReference, requirement: PackageRequirement)]
    ) {
        self.init(package: package)
        self.unversionedDeps = unversionedDependencies
            .map { PackageContainerConstraint(package: $0.package, requirement: $0.requirement) }
    }

    public convenience init(
        package: PackageReference,
        dependenciesByVersion: [Version: [(package: PackageReference, requirement: VersionSetSpecifier)]]
    ) {
        var dependencies: [String: [Dependency]] = [:]
        for (version, deps) in dependenciesByVersion {
            dependencies[version.description] = deps.map{
                ($0.package, .versionSet($0.requirement))
            }
        }
        self.init(package: package, dependencies: dependencies)
    }

    public init(
        package: PackageReference,
        dependencies: [String: [Dependency]] = [:]
    ) {
        self.package = package
        self.dependencies = dependencies
        let versions = dependencies.keys.compactMap(Version.init(_:))
        self._versions = versions
            .sorted()
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
        self.containersByIdentifier = Dictionary(uniqueKeysWithValues: containers.map({ ($0.package, $0) }))
    }

    public func getContainer(
        for package: PackageReference,
        skipUpdate: Bool,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Error>
    ) -> Void) {
        queue.async {
            completion(self.containersByIdentifier[package].map{ .success($0) } ??
                .failure(_MockLoadingError.unknownModule))
        }
    }
}

class DependencyGraphBuilder {
    private var containers: [String: MockContainer] = [:]
    private var references: [String: PackageReference] = [:]

    func reference(for packageName: String) -> PackageReference {
        if let reference = self.references[packageName] {
            return reference
        }
        let newReference = PackageReference.localSourceControl(identity: .plain(packageName), path: .init("/\(packageName)"))
        self.references[packageName] = newReference
        return newReference
    }

    func create(dependencies: OrderedDictionary<String, PackageRequirement>) -> [PackageContainerConstraint] {
        return dependencies.map {
            PackageContainerConstraint(package: reference(for: $0), requirement: $1)
        }
    }

    func serve(
        _ package: String,
        at version: Version,
        toolsVersion: ToolsVersion? = nil,
        with dependencies: KeyValuePairs<String, PackageRequirement> = [:]
    ) {
        serve(package, at: .version(version), toolsVersion: toolsVersion, with: dependencies)
    }

    func serve(
        _ package: String,
        at version: BoundVersion,
        toolsVersion: ToolsVersion? = nil,
        with dependencies: KeyValuePairs<String, PackageRequirement> = [:]
    ) {
        let packageReference = reference(for: package)
        let container = self.containers[package] ?? MockContainer(package: packageReference)

        if case .version(let v) = version {
            container.versionsToolsVersions[v] = toolsVersion ?? container.toolsVersion
        }

        container.appendVersion(version)

        let packageDependencies = dependencies.map {
            (container: reference(for: $0), requirement: $1)
        }
        container.dependencies[version.description] = packageDependencies
        self.containers[package] = container
    }

    /// Creates a pins store with the given pins.
    func create(pinsStore pins: [String: CheckoutState]) -> PinsStore {
        let fs = InMemoryFileSystem()
        let store = try! PinsStore(pinsFile: AbsolutePath("/tmp/Package.resolved"), workingDirectory: .root, fileSystem: fs, mirrors: .init())

        for (package, pinState) in pins {
            store.pin(packageRef: reference(for: package), state: pinState)
        }

        try! store.saveState(toolsVersion: ToolsVersion.currentToolsVersion)
        return store
    }

    func create(pinsMap: PinsStore.PinsMap = [:], log: Bool = false) -> PubgrubDependencyResolver {
        let delegate = log ? TracingDependencyResolverDelegate(stream: TSCBasic.stdoutStream) : nil
        return self.create(pinsMap: pinsMap, delegate: delegate)
    }

    func create(pinsMap: PinsStore.PinsMap = [:], delegate: DependencyResolverDelegate?) -> PubgrubDependencyResolver {
        defer {
            self.containers = [:]
            self.references = [:]
        }
        let provider = MockProvider(containers: self.containers.values.map { $0 })
        return PubgrubDependencyResolver(provider :provider, pinsMap: pinsMap, delegate: delegate)
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

        let packageReference = PackageReference(identity: .plain(components[0]), kind: .localSourceControl(.root), name: components[0])

        guard case let .versionSet(vs) = requirement! else {
            fatalError()
        }
        self.init(
            package:  packageReference,
            requirement: vs,
            isPositive: isPositive
        )
    }
}


extension PackageReference: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let ref = PackageReference.localSourceControl(identity: .plain(value), path: .root)
        self = ref
    }
}
extension Result where Success == [DependencyResolver.Binding] {
    var errorMsg: String? {
        switch self {
        case .failure(let error):
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
