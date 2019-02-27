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

/// Asserts that the listed packages are present in the bindings with their
/// specified versions.
private func AssertBindings(_ bindings: [DependencyResolver.Binding],
                            _ packages: [(identity: String, version: BoundVersion)],
                            file: StaticString = #file,
                            line: UInt = #line) {
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
private func AssertResult(_ result: PubgrubDependencyResolver.Result,
                          _ packages: [(identity: String, version: BoundVersion)],
                          file: StaticString = #file,
                          line: UInt = #line) {
    switch result {
    case .success(let bindings):
        AssertBindings(bindings, packages, file: file, line: line)
    case .unsatisfiable(dependencies: let constraints, pins: let pins):
        XCTFail("Unexpectedly unsatisfiable with dependencies: \(constraints) and pins: \(pins)", file: file, line: line)
    case .error(let error):
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

public typealias _MockPackageConstraint = PackageContainerConstraint
typealias PGError = PubgrubDependencyResolver.PubgrubError

public class MockContainer: PackageContainer {
    public typealias Dependency = (container: PackageReference, requirement: PackageRequirement)

    var name: PackageReference
    var manifestName: PackageReference?

    var dependencies: [String: [Dependency]]

    public var unversionedDeps: [_MockPackageConstraint] = []

    /// Contains the versions for which the dependencies were requested by resolver using getDependencies().
    public var requestedVersions: Set<Version> = []

    public var identifier: PackageReference {
        return name
    }

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
        if let manifestName = manifestName {
            name = name.with(newName: manifestName.identity)
        }
        return name
    }

    public convenience init(
        name: PackageReference,
        unversionedDependencies: [(package: PackageReference, requirement: VersionSetSpecifier)]
        ) {
        self.init(name: name)
        self.unversionedDeps = unversionedDependencies
            .map { _MockPackageConstraint(container: $0.package, versionRequirement: $0.requirement) }
    }

    public convenience init(
        name: PackageReference,
        dependenciesByVersion: [Version: [(package: PackageReference, requirement: VersionSetSpecifier)]]
        ) {
        var dependencies: [String: [Dependency]] = [:]
        for (version, deps) in dependenciesByVersion {
            dependencies[version.description] = deps.map({
                ($0.package, .versionSet($0.requirement))
            })
        }
        self.init(name: name, dependencies: dependencies)
    }

    public init(
        name: PackageReference,
        dependencies: [String: [Dependency]] = [:]
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
}

public struct MockProvider: PackageContainerProvider {

    public let containers: [MockContainer]
    public let containersByIdentifier: [PackageReference: MockContainer]

    public init(containers: [MockContainer]) {
        self.containers = containers
        self.containersByIdentifier = Dictionary(items: containers.map({ ($0.identifier, $0) }))
    }

    public func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, AnyError>
        ) -> Void) {
        DispatchQueue.global().async {
            completion(self.containersByIdentifier[identifier].map(Result.init) ??
                Result(_MockLoadingError.unknownModule))
        }
    }
}

class DependencyGraphBuilder {
    private var containers: [String: MockContainer] = [:]
    private var references: [String: PackageReference] = [:]

    private func reference(for packageName: String) -> PackageReference {
        if let reference = self.references[packageName] {
            return reference
        }
        let newReference = PackageReference(identity: packageName, path: "")
        self.references[packageName] = newReference
        return newReference
    }

    func serve(root: String, with dependencies: [String: VersionSetSpecifier]) {
        let rootDependencies = dependencies.keys.sorted().map {
            (package: reference(for: $0), requirement: dependencies[$0]!)
        }

        let rootContainer = MockContainer(name: reference(for: root),
                                          unversionedDependencies: rootDependencies)
        self.containers[root] = rootContainer
    }

    func serve(_ package: String, at version: Version, with dependencies: [String: VersionSetSpecifier] = [:]) {
        serve(package, at: .version(version), with: dependencies)
    }

    func serve(_ package: String, at version: BoundVersion, with dependencies: [String: VersionSetSpecifier] = [:]) {
        let packageReference = reference(for: package)
        let container = self.containers[package] ?? MockContainer(name: packageReference)

        container._versions.append(version)
        container._versions = container._versions
            .sorted(by: { lhs, rhs -> Bool in
                guard case .version(let lv) = lhs, case .version(let rv) = rhs else {
                    fatalError("Cannot sort BoundVersion's with non-version requirements.")
                }
                return lv < rv
            })
            .reversed()

        let packageDependencies = dependencies.map {
            (container: reference(for: $0), requirement: PackageRequirement.versionSet($1))
        }
        container.dependencies[version.description] = packageDependencies
        self.containers[package] = container
    }

    func create() -> PubgrubDependencyResolver {
        defer {
            self.containers = [:]
            self.references = [:]
        }
        let provider = MockProvider(containers: self.containers.values.map { $0 })
        return PubgrubDependencyResolver(provider, delegate)
    }
}

let builder = DependencyGraphBuilder()


public class _MockResolverDelegate: DependencyResolverDelegate {
    public typealias Identifier = PackageReference

    public init() {}

    var traceSteps: [TraceStep] = []

    public func trace(_ step: TraceStep) {
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



private let emptyProvider = MockProvider(containers: [])
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
let _cause = Incompatibility("cause@0.0.0", root: rootRef)

fileprivate func term(_ literal: String) -> Term {
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
        XCTAssertNil(term("a@1.0.0").difference(with: term("a@1.0.0")))

        XCTAssertEqual(
            term("¬a^1.0.0").intersect(with: term("a^2.0.0")),
            term("a^2.0.0"))

        XCTAssertEqual(
            term("a^2.0.0").intersect(with: term("¬a^1.0.0")),
            term("a^2.0.0"))

        XCTAssertEqual(
            term("¬a^1.0.0").intersect(with: term("¬a^1.0.0")),
            term("¬a^1.0.0"))

        XCTAssertEqual(
            term("¬a@1.0.0").intersect(with: term("¬a@1.0.0")),
            term("¬a@1.0.0"))

        // Check difference.
        let anyA = Term("a", .versionSet(.any))
        XCTAssertNil(term("a^1.0.0").difference(with: anyA))

        let notEmptyA = Term(not: "a", .versionSet(.empty))
        XCTAssertNil(term("a^1.0.0").difference(with: notEmptyA))
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

        let s2 = PartialSolution(assignments: [
            .derivation("¬a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a2 = s2._positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a2?.requirement, .versionSet(.range("1.0.0"..<"1.5.0")))
    }

    func testSolutionUndecided() {
        let solution = PartialSolution()
        solution.derive("a^1.0.0", cause: rootCause)
        solution.decide("b", at: .version("2.0.0"))
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

        let solution = PartialSolution(assignments: [])
        solution.decide(rootRef, at: .version("1.0.0"))
        solution.decide(aRef, at: .version("1.0.0"))
        solution.derive(b, cause: _cause)
        XCTAssertEqual(solution.decisionLevel, 1)

        XCTAssertEqual(solution.assignments, [
            .decision(root, decisionLevel: 0),
            .decision(a, decisionLevel: 1),
            .derivation(b, cause: _cause, decisionLevel: 1)
        ])
        XCTAssertEqual(solution.decisions, [
            rootRef: .version("1.0.0"),
            aRef: .version("1.0.0"),
        ])
    }

    func testSolutionBacktrack() {
        // TODO: This should probably add derivations to cover that logic as well.
        let solution = PartialSolution()
        solution.decide(aRef, at: .version("1.0.0"))
        solution.decide(bRef, at: .version("1.0.0"))
        solution.decide(cRef, at: .version("1.0.0"))

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

    func testUpdatePackageIdentifierAfterResolution() {
        let fooRef = PackageReference(identity: "foo", path: "https://some.url/FooBar")
        let foo = MockContainer(name: fooRef, dependenciesByVersion: [v1: []])
        foo.manifestName = "bar"

        let root = MockContainer(name: "root", unversionedDependencies: [(package: fooRef, requirement: v1Range)])
        let provider = MockProvider(containers: [root, foo])

        let resolver = PubgrubDependencyResolver(provider, delegate)
        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .error, .unsatisfiable:
            XCTFail("Unexpected error")
        case .success(let bindings):
            XCTAssertEqual(bindings.count, 1)
            let foo = bindings.first
            XCTAssertEqual(foo?.container.name, "bar")
        }
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

        let a = MockContainer(name: aRef, dependenciesByVersion: [
            v1: [(package: bRef, requirement: v1Range)]
        ])

        let provider = MockProvider(containers: [a])
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
            Incompatibility("a^1.0.0", "¬b^1.0.0",
                                              root: rootRef,
                                              cause: .dependency(package: "a"))
        ])
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
        solver1.solution.decide(aRef, at: .version("1.0.0"))
        // FIXME: This leads to fatal error.
        // try solver1.propagate(aRef)

        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        let solver2 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver2.add(Incompatibility(Term("root", .versionSet(.any)),
                                    term("¬a@1.0.0"),
                                    root: rootRef), location: .topLevel)
        solver2.solution.decide(rootRef, at: .version("1.0.0"))
        XCTAssertEqual(solver2.solution.assignments.count, 1)
        try solver2.propagate(PackageReference(identity: "root", path: ""))
        XCTAssertEqual(solver2.solution.assignments.count, 2)
    }

    func testSolutionFindSatisfiers() {
        let solution = PartialSolution()
        solution.decide(rootRef, at: .version("1.0.0")) // ← previous, but actually nil because this is the root decision
        solution.derive(Term(aRef, .versionSet(.any)), cause: _cause) // ← satisfier
        solution.decide(aRef, at: .version("2.0.0"))
        solution.derive("b^1.0.0", cause: _cause)

        XCTAssertEqual(solution.satisfier(for: term("b^1.0.0")) .term, "b^1.0.0")
        XCTAssertEqual(solution.satisfier(for: term("¬a^1.0.0")).term, "a@2.0.0")
        XCTAssertEqual(solution.satisfier(for: term("a^2.0.0")).term, "a@2.0.0")
    }

    func testMissingVersion() {
        builder.serve(root: "root", with: ["a": v2Range])
        builder.serve("a", at: v1_1)

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        switch result {
        case .error(let error):
            XCTAssertEqual("\(error)", "unresolvable({root 1.0.0})")
        default:
            XCTFail("Unexpected \(result)")
        }
    }

    func testResolutionNoConflicts() {
        builder.serve(root: "root", with: ["a": v1Range])
        builder.serve("a", at: v1, with: ["b": v1Range])
        builder.serve("b", at: v1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version(v1))
        ])
    }

    func testResolutionAvoidingConflictResolutionDuringDecisionMaking() {
        builder.serve(root: "root", with: ["a": v1Range, "b": v1Range])
        builder.serve("a", at: v1)
        builder.serve("a", at: v1_1, with: ["b": v2Range])
        builder.serve("b", at: v1)
        builder.serve("b", at: v1_1)
        builder.serve("b", at: v2)

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        AssertResult(result, [
            ("a", .version(v1)),
            ("b", .version("1.1.0"))
        ])
    }

    func testResolutionPerformingConflictResolution() {
        // Pubgrub has a listed as >=1.0.0, which we can't really represent here.
        // It's either .any or 1.0.0..<n.0.0 with n>2. Both should have the same
        // effect though.
        builder.serve(root: "root", with: ["a": .range("1.0.0"..<"3.0.0")])
        builder.serve("a", at: v1)
        builder.serve("a", at: v2, with: ["b": v1Range])
        builder.serve("b", at: v1, with: ["a": v1Range])

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        AssertResult(result, [
            ("a", .version(v1))
        ])
    }

    func testResolutionConflictResolutionWithAPartialSatisfier() {
        builder.serve(root: "root", with: ["foo": v1Range, "target": v2Range])
        builder.serve("foo", at: v1)
        builder.serve("foo", at: v1_1, with: ["left": v1Range, "right": v1Range])
        builder.serve("left", at: v1, with: ["shared": v1Range])
        builder.serve("right", at: v1, with: ["shared": v1Range])
        builder.serve("shared", at: v1, with: ["target": v1Range])
        builder.serve("shared", at: v2)
        builder.serve("target", at: v1)
        builder.serve("target", at: v2)

        // foo 1.1.0 transitively depends on a version of target that's not compatible
        // with root's constraint. This dependency only exists because of left
        // *and* right, choosing only one of these would be fine.

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        AssertResult(result, [
            ("foo", .version(v1)),
            ("target", .version(v2))
        ])
    }

    func DISABLED_testCycle1() {
        builder.serve(root: "root", with: ["foo": v1Range])
        builder.serve("foo", at: v1_1, with: ["foo": v1Range])

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        guard case .error = result else {
            return XCTFail("Expected a cycle")
        }
    }

    func DISABLED_testCycle2() {
        builder.serve(root: "root", with: ["foo": v1Range])
        builder.serve("foo", at: v1_1, with: ["bar": v1Range])
        builder.serve("bar", at: v1, with: ["baz": v1Range])
        builder.serve("baz", at: v1, with: ["bam": v1Range])
        builder.serve("bam", at: v1, with: ["baz": v1Range])

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        guard case .error = result else {
            return XCTFail("Expected a cycle")
        }
    }

    func testResolutionNonExistentVersion() {
        builder.serve(root: "root", with: ["package": .exact(v1)])
        builder.serve("package", at: "2.0.0")

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        guard
            case .error(let error) = result,
            let pubgrubError = error as? PGError,
            case .unresolvable(let incompatibility) = pubgrubError,
            case .conflict(let unavailable, _) = incompatibility.cause
        else {
            return XCTFail("Expected unresolvable graph.")
        }

        XCTAssertEqual(unavailable.description, "{package 1.0.0}")
    }

    func testNonExistentPackage() {
        builder.serve(root: "root", with: ["package": .exact(v1)])

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        guard
            case .error(let error) = result,
            let anyError = error as? AnyError,
            let mockError = anyError.underlyingError as? _MockLoadingError,
            case .unknownModule = mockError
        else {
            return XCTFail("Expected unknown module error.")
        }
    }

    func testConflict1() {
        builder.serve(root: "root", with: ["foo": v1Range, "bar": v1Range])
        builder.serve("foo", at: v1, with: ["config": v1Range])
        builder.serve("bar", at: v1, with: ["config": v2Range])
        builder.serve("config", at: v1)
        builder.serve("config", at: v2)

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])

        guard
            case .error(let error) = result,
            let pubgrubError = error as? PGError,
            case .unresolvable(let incompatibility) = pubgrubError,
            case .conflict(let cause, _) = incompatibility.cause
        else {
            return XCTFail("Expected unresolvable graph.")
        }

        XCTAssertEqual(cause.description, "{foo 1.0.0..<2.0.0}")
    }

    func testConflict2() {
        func addDeps() {
            builder.serve("foo", at: v1, with: ["config": v1Range])
            builder.serve("config", at: v1)
            builder.serve("config", at: v2)
        }

        builder.serve(root: "root", with: [
            "config": v2Range,
            "foo": v1Range,
        ])
        addDeps()
        let resolver1 = builder.create()
        _ = resolver1.solve(root: rootRef, pins: [])

        builder.serve(root: "root", with: [
            "foo": v1Range,
            "config": v2Range,
        ])
        addDeps()
        let resolver2 = builder.create()
        _ = resolver2.solve(root: rootRef, pins: [])
    }

    func testConflict3() {
        builder.serve(root: "root", with: [
            "foo": v1Range,
            "config": v2Range,
        ])
        builder.serve("foo", at: v1, with: ["config": v1Range])
        builder.serve("config", at: v1)

        let resolver = builder.create()
        let result = resolver.solve(root: rootRef, pins: [])
        guard
            case .error(let error) = result,
            let pubgrubError = error as? PGError,
            case .unresolvable(let incompatibility) = pubgrubError,
            case .conflict(let cause, _) = incompatibility.cause
        else {
            return XCTFail("Expected unresolvable graph.")
        }

        XCTAssertEqual(cause.description, "{foo 1.0.0..<2.0.0}")
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
        var requirement: PackageRequirement

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

        let packageReference = PackageReference(identity: components[0], path: "")

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
