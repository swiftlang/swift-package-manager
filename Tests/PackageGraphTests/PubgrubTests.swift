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

public typealias _MockPackageConstraint = PackageContainerConstraint<PackageReference>

public class _MockPackageContainer: PackageContainer {

    public typealias Identifier = PackageReference

    public typealias Dependency = (container: Identifier, requirement: PackageRequirement)

    let name: Identifier

    let dependencies: [String: [Dependency]]

    public var unversionedDeps: [_MockPackageConstraint] = []

    /// Contains the versions for which the dependencies were requested by resolver using getDependencies().
    public var requestedVersions: Set<Version> = []

    public var identifier: Identifier {
        return name
    }

    public let _versions: [Version]
    public func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version> {
        return AnySequence(_versions.filter(isIncluded))
    }

    public func getDependencies(at version: Version) -> [_MockPackageConstraint] {
        requestedVersions.insert(version)
        return getDependencies(at: version.description)
    }

    public func getDependencies(at revision: String) -> [_MockPackageConstraint] {
        return dependencies[revision]!.map({ value in
            let (name, requirement) = value
            return _MockPackageConstraint(container: name, requirement: requirement)
        })
    }

    public func getUnversionedDependencies() -> [_MockPackageConstraint] {
        return unversionedDeps
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        return name
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
        let versions = dependencies.keys.compactMap(Version.init(string:))
        self._versions = versions.sorted().reversed()
        self.dependencies = dependencies
    }
}

public enum _MockLoadingError: Error {
    case unknownModule
}

public struct _MockPackageProvider: PackageContainerProvider {
    public typealias Container = _MockPackageContainer

    public let containers: [Container]
    public let containersByIdentifier: [Container.Identifier: Container]

    public init(containers: [_MockPackageContainer]) {
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
                Result(_MockLoadingError.unknownModule))
        }
    }
}

public class _MockResolverDelegate: DependencyResolverDelegate {
    public typealias Identifier = _MockPackageContainer.Identifier

    public init() {}

    var traceSteps: [TraceStep<Identifier>] = []

    public func trace(_ step: TraceStep<Identifier>) {
        traceSteps.append(step)
    }

    func traceDescription() -> String {
        let headers = ["Step", "Value", "Type", "Location", "Cause", "Dec. Lvl."]
        let values = traceSteps
            .compactMap { step -> GeneralTraceStep? in
                if case .general(let generalStep) = step {
                    return generalStep
                }
                return nil
            }
            .enumerated()
            .map { val -> [String] in
                let (idx, s) = val
                return [
                    "\(idx + 1)",
                    s.value.description,
                    s.type.rawValue,
                    s.location.rawValue,
                    s.cause ?? "",
                    String(s.decisionLevel)
                ]
            }
        return textTable([headers] + values)
    }

    func textTable(_ data: [[String]]) -> String {
        guard let firstRow = data.first, !firstRow.isEmpty else {
            return ""
        }

        func maxWidth(_ array: [String]) -> Int {
            guard let maxElement = array.max(by: { $0.count < $1.count }) else {
                return 0
            }
            return maxElement.count
        }

        func pad(_ string: String, _ padding: Int) -> String {
            let padding = padding - (string.count - 1)
            guard padding >= 0 else {
                return string
            }
            return " " + string + Array(repeating: " ", count: padding).joined()
        }

        var columns = [[String]]()
        for i in 0..<firstRow.count {
            columns.append(data.map { $0[i] })
        }

        let dividerLine = columns
            .map { Array(repeating: "-", count: maxWidth($0) + 2).joined() }
            .reduce("+") { $0 + $1 + "+" }

        return data
            .reduce([dividerLine]) { result, row -> [String] in
                let rowString = zip(row, columns)
                    .map { pad(String(describing: $0), maxWidth($1)) }
                    .reduce("|") { $0 + $1 + "|" }
                return result + [rowString, dividerLine]}
            .joined(separator: "\n")
    }
}



private let emptyProvider = _MockPackageProvider(containers: [])
private let delegate = _MockResolverDelegate()

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

let aRef = PackageReference(identity: "a", path: "")
let bRef = PackageReference(identity: "b", path: "")
let cRef = PackageReference(identity: "c", path: "")

let rootRef = PackageReference(identity: "root", path: "")
let rootCause = Incompatibility(Term(rootRef, .versionSet(.exact("1.0.0"))), root: rootRef)
let _cause = Incompatibility<PackageReference>("cause@0.0.0", root: rootRef)

fileprivate func term(_ literal: String) -> Term<PackageReference> {
    return Term(stringLiteral: literal)
}


final class PubgrubTests: XCTestCase {
    func testTermInverse() {
        let a = term("a@1.0.0")
        XCTAssertFalse(a.inverse.isPositive)
        XCTAssertTrue(a.inverse.inverse.isPositive)
    }

    func testTermSatisfies() {
        let a100 = term("a@1.0.0")

        XCTAssertTrue(a100.satisfies(a100))
        XCTAssertFalse(a100.satisfies("¬a@1.0.0"))
        XCTAssertTrue(a100.satisfies("a^1.0.0"))
        XCTAssertFalse(a100.satisfies("¬a^1.0.0"))
        XCTAssertFalse(a100.satisfies("a^2.0.0"))

        XCTAssertFalse(a100.satisfies(Term(bRef, .unversioned)))

        XCTAssertFalse(term("¬a@1.0.0").satisfies("¬a^1.0.0"))
        XCTAssertFalse(term("¬a@1.0.0").satisfies("a^2.0.0"))
        XCTAssertTrue(term("¬a^1.0.0").satisfies("¬a@1.0.0"))
        XCTAssertTrue(term("a^2.0.0").satisfies("¬a@1.0.0"))

        XCTAssertTrue(term("a^1.0.0").satisfies("¬a@2.0.0"))
        XCTAssertTrue(term("a^1.0.0").satisfies("¬a^2.0.0"))

        XCTAssertTrue(term("a^1.0.0").satisfies(term("a^1.0.0")))
        XCTAssertTrue(term("a-1.0.0-1.1.0").satisfies(term("a^1.0.0")))
        XCTAssertFalse(term("a-1.0.0-1.1.0").satisfies(term("a^2.0.0")))
    }

    func testTermIntersection() {
        // a^1.0.0 ∩ ¬a@1.5.0 → a >=1.0.0 <1.5.0
        XCTAssertEqual(
            term("a^1.0.0").intersect(with: term("¬a@1.5.0")),
            term("a-1.0.0-1.5.0"))

        // a^1.0.0 ∩ a >=1.5.0 <3.0.0 → a^1.5.0
        XCTAssertEqual(
            term("a^1.0.0").intersect(with: term("a-1.5.0-3.0.0")),
            term("a^1.5.0"))

        // ¬a^1.0.0 ∩ ¬a >=1.5.0 <3.0.0 → ¬a >=1.0.0 <3.0.0
        XCTAssertEqual(
            term("¬a^1.0.0").intersect(with: term("¬a-1.5.0-3.0.0")),
            term("¬a-1.0.0-3.0.0"))

        XCTAssertEqual(
            term("a^1.0.0").intersect(with: term("a^1.0.0")),
            term("a^1.0.0"))

        XCTAssertEqual(
            term("¬a^1.0.0").intersect(with: term("¬a^1.0.0")),
            term("¬a^1.0.0"))

        XCTAssertNil(term("a^1.0.0").intersect(with: term("¬a^1.0.0")))

        XCTAssertEqual(
            term("¬a^1.0.0").intersect(with: term("a^2.0.0")),
            term("a^2.0.0"))

        XCTAssertEqual(
            term("a^2.0.0").intersect(with: term("¬a^1.0.0")),
            term("a^2.0.0"))
    }

    func testTermRelation() {
        // Both positive.
        XCTAssertEqual(term("a^1.1.0").relation(with: "a^1.0.0"), .subset)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a^1.8.9"), .subset)
        XCTAssertEqual(term("a^1.5.0").relation(with: "a^1.0.0"), .subset)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a@1.9.0"), .overlap)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a@1.9.1"), .overlap)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a@1.20.0"), .overlap)
        XCTAssertEqual(term("a^2.0.0").relation(with: "a^2.9.0"), .overlap)
        XCTAssertEqual(term("a^2.0.0").relation(with: "a^2.9.0"), .overlap)
        XCTAssertEqual(term("a-1.5.0-3.0.0").relation(with: "a^1.0.0"), .overlap)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a@1.8.1"), .disjoint)
        XCTAssertEqual(term("a^1.9.0").relation(with: "a@2.0.0"), .disjoint)
        XCTAssertEqual(term("a^2.0.0").relation(with: "a@1.0.0"), .disjoint)

        // First term is negative, second term is positive.
        XCTAssertEqual(term("¬a^1.0.0").relation(with: "a@1.5.0"), .disjoint)
        XCTAssertEqual(term("¬a^1.5.0").relation(with: "a^1.0.0"), .overlap)
        XCTAssertEqual(term("¬a^2.0.0").relation(with: "a^1.5.0"), .overlap)

        // First term is positive, second term is negative.
        XCTAssertEqual(term("a^2.0.0").relation(with: "¬a^1.0.0"), .subset)
        XCTAssertEqual(term("a^1.5.0").relation(with: "¬a^1.0.0"), .disjoint)
        XCTAssertEqual(term("a^1.0.0").relation(with: "¬a^1.5.0"), .overlap)

        // Both terms are negative.
        XCTAssertEqual(term("¬a^1.0.0").relation(with: "¬a^1.5.0"), .subset)
        XCTAssertEqual(term("¬a^2.0.0").relation(with: "¬a^1.0.0"), .overlap)
        XCTAssertEqual(term("¬a^1.5.0").relation(with: "¬a^1.0.0"), .overlap)
    }

    func testTermIsValidDecision() {
        let solution100_150 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 1),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 2)
        ])

        let allSatisfied = term("a@1.6.0")
        XCTAssertTrue(allSatisfied.isValidDecision(for: solution100_150))
        let partiallySatisfied = term("a@1.2.0")
        XCTAssertFalse(partiallySatisfied.isValidDecision(for: solution100_150))
    }

    func testIncompatibilityNormalizeTermsOnInit() {
        let i1 = Incompatibility(term("a^1.0.0"), term("a^1.5.0"), term("¬b@1.0.0"),
                                 root: rootRef)
        XCTAssertEqual(i1.terms.count, 2)
        let a1 = i1.terms.first { $0.package == "a" }
        let b1 = i1.terms.first { $0.package == "b" }
        XCTAssertEqual(a1?.requirement, .versionSet(.range("1.5.0"..<"2.0.0")))
        XCTAssertEqual(b1?.requirement, .versionSet(.exact("1.0.0")))

        let i2 = Incompatibility(term("¬a^1.0.0"), term("a^2.0.0"),
                                 root: rootRef)
        XCTAssertEqual(i2.terms.count, 1)
        let a2 = i2.terms.first
        XCTAssertEqual(a2?.requirement, .versionSet(.range("2.0.0"..<"3.0.0")))
    }

    func testSolutionPositive() {
        let s1 = PartialSolution(assignments:[
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("b@2.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a1 = s1._positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a1?.requirement, .versionSet(.range("1.5.0"..<"2.0.0")))
        let b1 = s1._positive.first { $0.key.identity == "b" }?.value
        XCTAssertEqual(b1?.requirement, .versionSet(.exact("2.0.0")))

        let s2 = PartialSolution<PackageReference>(assignments: [
            .derivation("¬a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a2 = s2._positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a2?.requirement, .versionSet(.range("1.0.0"..<"1.5.0")))
    }

    func testSolutionUndecided() {
        let solution = PartialSolution<PackageReference>()
        solution.derive("a^1.0.0", cause: rootCause)
        solution.decide("b", atExactVersion: "2.0.0")
        solution.derive("a^1.5.0", cause: rootCause)
        solution.derive("¬c^1.5.0", cause: rootCause)
        solution.derive("d^1.9.0", cause: rootCause)
        solution.derive("d^1.9.9", cause: rootCause)

        let undecided = solution.undecided.sorted{ $0.package.identity < $1.package.identity }
        XCTAssertEqual(undecided, [term("a^1.5.0"), term("d^1.9.9")])
    }

    func testSolutionAddAssignments() {
        let root = term("root@1.0.0")
        let a = term("a@1.0.0")
        let b = term("b@2.0.0")

        let solution = PartialSolution<PackageReference>(assignments: [])
        solution.decide(rootRef, atExactVersion: "1.0.0")
        solution.decide(aRef, atExactVersion: "1.0.0")
        solution.derive(b, cause: _cause)
        XCTAssertEqual(solution.decisionLevel, 1)

        XCTAssertEqual(solution.assignments, [
            .decision(root, decisionLevel: 0),
            .decision(a, decisionLevel: 1),
            .derivation(b, cause: _cause, decisionLevel: 1)
        ])
        XCTAssertEqual(solution.decisions, [
            rootRef: "1.0.0",
            aRef: "1.0.0",
        ])
    }

    func testSolutionBacktrack() {
        // TODO: This should probably add derivations to cover that logic as well.
        let solution = PartialSolution<PackageReference>()
        solution.decide(aRef, atExactVersion: "1.0.0")
        solution.decide(bRef, atExactVersion: "1.0.0")
        solution.decide(cRef, atExactVersion: "1.0.0")

        XCTAssertEqual(solution.decisionLevel, 2)
        solution.backtrack(toDecisionLevel: 1)
        XCTAssertEqual(solution.assignments.count, 2)
        XCTAssertEqual(solution.decisionLevel, 1)
    }

    func testPositiveTerms() {
        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
        ])
        XCTAssertEqual(s1._positive["a"]?.requirement,
                       .versionSet(.range("1.0.0"..<"2.0.0")))

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0)
        ])
        XCTAssertEqual(s2._positive["a"]?.requirement,
                       .versionSet(.range("1.5.0"..<"2.0.0")))
    }

    func testResolverAddIncompatibility() {
        let solver = PubgrubDependencyResolver(emptyProvider, delegate)

        let a = Incompatibility(term("a@1.0.0"), root: rootRef)
        solver.add(a, location: .topLevel)
        let ab = Incompatibility(term("a@1.0.0"), term("b@2.0.0"), root: rootRef)
        solver.add(ab, location: .topLevel)

        XCTAssertEqual(solver.incompatibilities, [
            "a": [a, ab],
            "b": [ab],
        ])
    }

    func testResolverConflictResolution() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.set(rootRef)

        let notRoot = Incompatibility(Term(not: rootRef, .versionSet(.any)),
                                      root: rootRef,
                                      cause: .root)
        solver1.add(notRoot, location: .topLevel)
        XCTAssertThrowsError(try solver1._resolve(conflict: notRoot))
    }

    func testResolverDecisionMaking() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.set(rootRef)

        // No decision can be made if no unsatisfied terms are available.
        XCTAssertNil(try solver1.makeDecision())


        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1: [(container: bRef, versionRequirement: v1Range)]
        ])
        let provider = _MockPackageProvider(containers: [a])
        let solver2 = PubgrubDependencyResolver(provider, delegate)

        let solution = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])
        solver2.solution = solution
        solver2.set(rootRef)

        XCTAssertEqual(solver2.incompatibilities.count, 0)

        let decision = try! solver2.makeDecision()
        XCTAssertEqual(decision, "a")

        XCTAssertEqual(solver2.incompatibilities.count, 2)
        XCTAssertEqual(solver2.incompatibilities["a"], [
            Incompatibility<PackageReference>("a^1.0.0", "¬b^1.0.0",
                                              root: rootRef,
                                              cause: .dependency(package: "a"))
        ])
    }

    func testResolutionNoConflicts() {
        let root = _MockPackageContainer(name: rootRef)
        root.unversionedDeps = [_MockPackageConstraint(container: aRef, versionRequirement: v1Range)]
        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1: [(container: bRef, versionRequirement: v1Range)]
        ])
        let b = _MockPackageContainer(name: bRef, dependenciesByVersion: [
            v1: [],
            v2: []
        ])

        let provider = _MockPackageProvider(containers: [root, a, b])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 2)
            let a = bindings.first { $0.container.identity == "a" }
            let b = bindings.first { $0.container.identity == "b" }
            XCTAssertEqual(a?.binding, .version("1.0.0"))
            XCTAssertEqual(b?.binding, .version("1.0.0"))
        case .error(let error):
            XCTFail("Unexpected error: \(error)")
        case .unsatisfiable(dependencies: let constraints, pins: let pins):
            XCTFail("Unexpectedly unsatisfiable with dependencies: \(constraints) and pins: \(pins)")
        }
    }

    func testResolutionAvoidingConflictResolutionDuringDecisionMaking() {
        let root = _MockPackageContainer(name: rootRef)
        root.unversionedDeps = [
            _MockPackageConstraint(container: aRef, versionRequirement: v1Range),
            _MockPackageConstraint(container: bRef, versionRequirement: v1Range)
        ]
        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1: [],
            v1_1: [(container: bRef, versionRequirement: v2Range)]
        ])
        let b = _MockPackageContainer(name: bRef, dependenciesByVersion: [
            v1: [],
            v1_1: [],
            v2: []
        ])

        let provider = _MockPackageProvider(containers: [root, a, b])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 2)
            let a = bindings.first { $0.container.identity == "a" }
            let b = bindings.first { $0.container.identity == "b" }
            XCTAssertEqual(a?.binding, .version("1.0.0"))
            XCTAssertEqual(b?.binding, .version("1.1.0"))
        case .error(let error):
            XCTFail("Unexpected error: \(error)")
        case .unsatisfiable(dependencies: let constraints, pins: let pins):
            XCTFail("Unexpectedly unsatisfiable with dependencies: \(constraints) and pins: \(pins)")
        }
    }

    func _testResolutionPerformingConflictResolution() {
        let root = _MockPackageContainer(name: rootRef)
        root.unversionedDeps = [
            // Pubgrub has a listed as >=1.0.0, which we can't really represent
            // here... It's either .any or 1.0.0..<n.0.0 with n>2. Both should
            // have the same effect though.
            _MockPackageConstraint(container: aRef, versionRequirement: .range("1.0.0"..<"3.0.0"))
            // FIXME: .any is not working probably because of a bad insersection computation.
            // _MockPackageConstraint(container: aRef, versionRequirement: .any)
        ]
        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1: [],
            v2: [(container: bRef, versionRequirement: v1Range)]
        ])
        let b = _MockPackageContainer(name: bRef, dependenciesByVersion: [
            v1: [(container: aRef, versionRequirement: v1Range)]
        ])

        let provider = _MockPackageProvider(containers: [root, a, b])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 1)
            let a = bindings.first
            XCTAssertEqual(a?.container, "a")
            XCTAssertEqual(a?.binding, .version("1.0.0"))
        case .error(let error):
            XCTFail("Unexpected error: \(error)")
        case .unsatisfiable(dependencies: let constraints, pins: let pins):
            XCTFail("Unexpectedly unsatisfiable with dependencies: \(constraints) and pins: \(pins)")
        }
    }

    func testResolverUnitPropagation() throws {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)

        // no known incompatibilities should result in no satisfaction checks
        try solver1.propagate("root")

        // even if incompatibilities are present
        solver1.add(Incompatibility(term("a@1.0.0"), root: rootRef), location: .topLevel)
        try solver1.propagate("a")
        try solver1.propagate("a")
        try solver1.propagate("a")

        // adding a satisfying term should result in a conflict
        solver1.solution.decide(aRef, atExactVersion: "1.0.0")
        // FIXME: This leads to fatal error.
        // try solver1.propagate(aRef)

        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        let solver2 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver2.add(Incompatibility(Term("root", .versionSet(.any)),
                                    term("¬a@1.0.0"),
                                    root: rootRef), location: .topLevel)
        solver2.solution.decide(rootRef, atExactVersion: "1.0.0")
        XCTAssertEqual(solver2.solution.assignments.count, 1)
        try solver2.propagate(PackageReference(identity: "root", path: ""))
        XCTAssertEqual(solver2.solution.assignments.count, 2)
    }

    func testSolutionFindSatisfiers() {
        let solution = PartialSolution<PackageReference>()
        solution.decide(rootRef, atExactVersion: "1.0.0") // ← previous, but actually nil because this is the root decision
        solution.derive(Term(aRef, .versionSet(.any)), cause: _cause) // ← satisfier
        solution.decide(aRef, atExactVersion: "2.0.0")
        solution.derive("b^1.0.0", cause: _cause)

        XCTAssertEqual(solution.satisfier(for: term("b^1.0.0")) .term, "b^1.0.0")
        XCTAssertEqual(solution.satisfier(for: term("¬a^1.0.0")).term, "a@2.0.0")
        XCTAssertEqual(solution.satisfier(for: term("a^2.0.0")).term, "a@2.0.0")
    }

    func testMissingVersion() {
        let root = _MockPackageContainer(name: rootRef)
        root.unversionedDeps = [
            _MockPackageConstraint(container: aRef, versionRequirement: v2Range),
        ]
        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1_1: []
        ])

        let provider = _MockPackageProvider(containers: [root, a])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .error(let error):
            XCTAssertEqual("\(error)", "unresolvable({root 1.0.0})")
        default:
            XCTFail("Unexpected \(result)")
        }
    }

    func testResolutionConflictResolutionWithAPartialSatisfier() {
        let root = _MockPackageContainer(name: rootRef)
        let fooRef = PackageReference(identity: "foo", path: "")
        let leftRef = PackageReference(identity: "left", path: "")
        let rightRef = PackageReference(identity: "right", path: "")
        let sharedRef = PackageReference(identity: "shared", path: "")
        let targetRef = PackageReference(identity: "target", path: "")

        root.unversionedDeps = [
            _MockPackageConstraint(container: fooRef, versionRequirement: v1Range),
            _MockPackageConstraint(container: targetRef, versionRequirement: v2Range)
        ]
        let foo = _MockPackageContainer(name: fooRef, dependenciesByVersion: [
            v1: [],
            v1_1: [
                (container: leftRef, versionRequirement: v1Range),
                (container: rightRef, versionRequirement: v1Range)
            ]
        ])
        let left = _MockPackageContainer(name: leftRef, dependenciesByVersion: [
            v1: [(container: sharedRef, versionRequirement: v1Range)]
        ])
        let right = _MockPackageContainer(name: rightRef, dependenciesByVersion: [
            v1: [(container: sharedRef, versionRequirement: v1Range)]
        ])
        let shared = _MockPackageContainer(name: sharedRef, dependenciesByVersion: [
            v1: [(container: targetRef, versionRequirement: v1Range)],
            v2: []
        ])
        let target = _MockPackageContainer(name: targetRef, dependenciesByVersion: [
            v1: [],
            v2: []
        ])

        // foo 1.1.0 transitively depends on a version of target that's not compatible
        // with root's constraint. This dependency only exists because of left
        // *and* right, choosing only one of these would be fine.

        let provider = _MockPackageProvider(containers: [root, foo, left, right, shared, target])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 2)
            let foo = bindings.first { $0.container == "foo" }
            let target = bindings.first { $0.container == "target" }
            XCTAssertEqual(foo?.binding, .version("1.0.0"))
            XCTAssertEqual(target?.binding, .version("2.0.0"))
        case .unsatisfiable(dependencies: let constraints, pins: let pins):
            XCTFail("Unexpectedly unsatisfiable with dependencies: \(constraints) and pins: \(pins)")
        case .error(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func DISABLED_testCycle1() {
        let root = _MockPackageContainer(name: rootRef)
        let fooRef = PackageReference(identity: "foo", path: "")

        root.unversionedDeps = [
            _MockPackageConstraint(container: fooRef, versionRequirement: v1Range),
        ]
        let foo = _MockPackageContainer(name: fooRef, dependenciesByVersion: [
            v1_1: [
                (container: fooRef, versionRequirement: v1Range),
            ]
        ])

        let provider = _MockPackageProvider(containers: [root, foo])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        guard case .error = result else {
            return XCTFail("Expected a cycle")
        }
    }

    func DISABLED_testCycle2() {
        let root = _MockPackageContainer(name: rootRef)
        let fooRef = PackageReference(identity: "foo", path: "")
        let barRef = PackageReference(identity: "bar", path: "")
        let bazRef = PackageReference(identity: "baz", path: "")
        let bamRef = PackageReference(identity: "bam", path: "")

        root.unversionedDeps = [
            _MockPackageConstraint(container: fooRef, versionRequirement: v1Range),
        ]
        let foo = _MockPackageContainer(name: fooRef, dependenciesByVersion: [
            v1_1: [
                (container: barRef, versionRequirement: v1Range),
            ]
            ])
        let bar = _MockPackageContainer(name: barRef, dependenciesByVersion: [
            v1: [(container: bazRef, versionRequirement: v1Range)]
            ])
        let baz = _MockPackageContainer(name: bazRef, dependenciesByVersion: [
            v1: [(container: bamRef, versionRequirement: v1Range)]
            ])
        let bam = _MockPackageContainer(name: bamRef, dependenciesByVersion: [
            v1: [(container: bazRef, versionRequirement: v1Range)]
        ])

        let provider = _MockPackageProvider(containers: [root, foo, bar, baz, bam])
        let resolver = PubgrubDependencyResolver(provider, delegate)

        let result = resolver.solve(root: rootRef, pins: [])

        guard case .error = result else {
            return XCTFail("Expected a cycle")
        }
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
        } else if value.contains("-") {
            components = value.split(separator: "-").map(String.init)
            assert(components.count == 3, "expected `name-lowerBound-upperBound`")
            let (lowerBound, upperBound) = (components[1], components[2])
            requirement = .versionSet(.range(Version(stringLiteral: lowerBound)..<Version(stringLiteral: upperBound)))
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

    init(_ name: String) {
        self.init(identity: name, path: "")
    }
}
