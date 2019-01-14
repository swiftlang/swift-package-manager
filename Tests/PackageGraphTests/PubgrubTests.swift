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

    public typealias Dependency = (container: Identifier, requirement: _MockPackageConstraint.Requirement)

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

    var traceSteps: [TraceStep] = []

    public func trace(_ step: TraceStep) {
        traceSteps.append(step)
    }

    func traceDescription() -> String {
        let headers = ["Step", "Value", "Type", "Location", "Cause", "Dec. Lvl."]
        let values = traceSteps.enumerated().map { val -> [String] in
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

let rootRef = PackageReference(identity: "root", path: "")
let rootCause = Incompatibility(Term(rootRef, .versionSet(.exact("1.0.0"))))
let _cause = Incompatibility<PackageReference>("cause@0.0.0")

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

        XCTAssertTrue(term("¬a@1.0.0").satisfies("¬a^1.0.0"))
        XCTAssertTrue(term("¬a@1.0.0").satisfies("a^2.0.0"))
        XCTAssertTrue(term("a^1.0.0").satisfies("¬a@2.0.0"))
        XCTAssertTrue(term("a^1.0.0").satisfies("¬a^2.0.0"))

        XCTAssertTrue(term("a^1.0.0").satisfies(term("a^1.0.0")))
        XCTAssertTrue(term("a-1.0.0-1.1.0").satisfies(term("a^1.0.0")))
        XCTAssertFalse(term("a-1.0.0-1.1.0").satisfies(term("a^2.0.0")))

        XCTAssertTrue(
            Term(aRef, .revision("ab")).satisfies(
            Term(aRef, .revision("ab"))))
        XCTAssertFalse(
            Term(aRef, .revision("ab")).satisfies(
            Term(aRef, .revision("ba"))))
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
        let i = Incompatibility(term("a^1.0.0"), term("a^1.5.0"), term("¬b@1.0.0"))
        XCTAssertEqual(i.terms.count, 2)
        let a = i.terms.first { $0.package == "a" }
        let b = i.terms.first { $0.package == "b" }
        XCTAssertEqual(a?.requirement, .versionSet(.range("1.5.0"..<"2.0.0")))
        XCTAssertEqual(b?.requirement, .versionSet(.exact("1.0.0")))
    }

    func testSolutionPositive() {
        let s1 = PartialSolution(assignments:[
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("b@2.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a1 = s1.positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a1?.requirement, .versionSet(.range("1.5.0"..<"2.0.0")))
        let b1 = s1.positive.first { $0.key.identity == "b" }?.value
        XCTAssertEqual(b1?.requirement, .versionSet(.exact("2.0.0")))

        let s2 = PartialSolution<PackageReference>(assignments: [
            .derivation("¬a^1.5.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0)
        ])
        let a2 = s2.positive.first { $0.key.identity == "a" }?.value
        XCTAssertEqual(a2?.requirement, .versionSet(.range("1.0.0"..<"1.5.0")))
    }

    func testSolutionUndecided() {
        let solution = PartialSolution<PackageReference>(assignments: [
            .derivation("a^1.5.0", cause: rootCause, decisionLevel: 0),
            .decision("b@2.0.0", decisionLevel: 0),
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])

        XCTAssertEqual(solution.undecided, [term("a^1.5.0")])
    }

    func testSolutionSatisfiesIncompatibility() {
        let s1 = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s1.satisfies(Incompatibility("a@1.0.0")),
                       .satisfied)

        let s2 = PartialSolution<PackageReference>(assignments: [
            .decision("b@2.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s2.satisfies(Incompatibility("¬a@1.0.0", "b@2.0.0")),
                       .almostSatisfied(except: "¬a@1.0.0"))

        let s3 = PartialSolution<PackageReference>(assignments: [
            .decision("c@3.0.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s3.satisfies(Incompatibility("¬a@1.0.0", "b@2.0.0")),
                       .unsatisfied)

        let s4 = PartialSolution<PackageReference>(assignments: [])
        XCTAssertEqual(s4.satisfies(Incompatibility("a@1.0.0")),
                       .unsatisfied)

        let s5 = PartialSolution<PackageReference>(assignments: [
            .decision("root@1.0.0", decisionLevel: 0),
            .decision("a@0.1.0", decisionLevel: 0),
            .decision("b@0.2.0", decisionLevel: 0)
        ])
        XCTAssertEqual(s5.satisfies(Incompatibility("root@1.0.0", "b@0.2.0")),
                       .satisfied)
    }

    func testSolutionAddAssignments() {
        let a = term("a@1.0.0")
        let b = term("b@2.0.0")

        let solution = PartialSolution<PackageReference>(assignments: [])
        solution.decide(aRef, atExactVersion: "1.0.0")
        solution.derive(b, cause: _cause)

        XCTAssertEqual(solution.decisionLevel, 1)
        XCTAssertEqual(solution.assignments, [
            .decision(a, decisionLevel: 0),
            .derivation(b, cause: _cause, decisionLevel: 1)
        ])
    }

    func testSolutionFindSatisfiers() {
        let s3 = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 0),
            .decision("b@2.0.0", decisionLevel: 0),
            .decision("c@3.0.0", decisionLevel: 0)
        ])

        let ac = Incompatibility<PackageReference>("a@1.0.0", "c@3.0.0")
        let (previous1, satisfier1) = s3.earliestSatisfiers(for: ac)
        XCTAssertEqual(previous1!.term, "a@1.0.0")
        XCTAssertEqual(satisfier1!.term, "c@3.0.0")

        let s2 = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 0),
            .decision("b@2.0.0", decisionLevel: 0)
        ])

        let ab = Incompatibility<PackageReference>("a@1.0.0", "b@2.0.0")
        let (previous2, satisfier2) = s2.earliestSatisfiers(for: ab)
        XCTAssertEqual(previous2!.term, "a@1.0.0")
        XCTAssertEqual(satisfier2!.term, "b@2.0.0")

        let s1 = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 0)
        ])

        let a = Incompatibility<PackageReference>("a@1.0.0")
        let (previous3, satisfier3) = s1.earliestSatisfiers(for: a)
        XCTAssertEqual(previous3!.term, "a@1.0.0")
        XCTAssertEqual(previous3, satisfier3)
    }

    func testSolutionBacktrack() {
        let solution = PartialSolution<PackageReference>(assignments: [
            .decision("a@1.0.0", decisionLevel: 1),
            .decision("b@1.0.0", decisionLevel: 2),
            .decision("c@1.0.0", decisionLevel: 3),
        ])

        XCTAssertEqual(solution.decisionLevel, 3)
        solution.backtrack(toDecisionLevel: 1)
        XCTAssertEqual(solution.assignments.count, 1)
        XCTAssertEqual(solution.decisionLevel, 1)
    }

    func testSolutionVersionIntersection() {
        let s1 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
        ])
        XCTAssertEqual(s1.versionIntersection(for: "a")?.requirement,
                       .versionSet(.range("1.0.0"..<"2.0.0")))

        let s2 = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: _cause, decisionLevel: 0),
            .derivation("a^1.5.0", cause: _cause, decisionLevel: 0)
        ])
        XCTAssertEqual(s2.versionIntersection(for: "a")?.requirement,
                       .versionSet(.range("1.5.0"..<"2.0.0")))
    }

    func testResolverAddIncompatibility() {
        let solver = PubgrubDependencyResolver(emptyProvider, delegate)

        let a = Incompatibility(term("a@1.0.0"))
        solver.add(a, location: .topLevel)
        let ab = Incompatibility(term("a@1.0.0"), term("b@2.0.0"))
        solver.add(ab, location: .topLevel)

        XCTAssertEqual(solver.incompatibilities, [
            "a": [a, ab],
            "b": [ab],
        ])
    }

    func testResolverUnitPropagation() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)

        // no known incompatibilities should result in no satisfaction checks
        XCTAssertNil(solver1.propagate("root"))

        // even if incompatibilities are present
        solver1.add(Incompatibility(term("a@1.0.0")), location: .topLevel)
        XCTAssertNil(solver1.propagate("a"))

        // adding a satisfying term should result in a conflict
        solver1.solution.decide(aRef, atExactVersion: "1.0.0")
        XCTAssertEqual(solver1.propagate(aRef), Incompatibility(term("a@1.0.0")))

        // Unit propagation should derive a new assignment from almost satisfied incompatibilities.
        let solver2 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver2.add(Incompatibility(Term("root", .versionSet(.any)),
                                    term("¬a@1.0.0")), location: .topLevel)
        solver2.solution.decide(rootRef, atExactVersion: "1.0.0")
        XCTAssertEqual(solver2.solution.assignments.count, 1)
        XCTAssertNil(solver2.propagate(PackageReference(identity: "root", path: "")))
        XCTAssertEqual(solver2.solution.assignments.count, 2)
    }

    func testResolverConflictResolution() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.root = rootRef

        let notRoot = Incompatibility(Term(not: rootRef, .versionSet(.any)), cause: .root)
        solver1.add(notRoot, location: .topLevel)
        XCTAssertNil(solver1.resolve(conflict: notRoot))
    }

    func testResolverDecisionMaking() {
        let solver1 = PubgrubDependencyResolver(emptyProvider, delegate)
        solver1.root = rootRef

        // No decision can be made if no unsatisfied terms are available.
        XCTAssertNil(try solver1.makeDecision())


        let a = _MockPackageContainer(name: aRef, dependenciesByVersion: [
            v1: [(container: bRef, versionRequirement: v1Range)]
        ])
        let provider = _MockPackageProvider(containers: [a])
        let solver2 = PubgrubDependencyResolver(provider, delegate)
        solver2.root = rootRef

        let solution = PartialSolution(assignments: [
            .derivation("a^1.0.0", cause: rootCause, decisionLevel: 0)
        ])
        solver2.solution = solution

        XCTAssertEqual(solver2.incompatibilities.count, 0)

        let decision = try! solver2.makeDecision()
        XCTAssertEqual(decision, "a")

        XCTAssertEqual(solver2.incompatibilities.count, 2)
        XCTAssertEqual(solver2.incompatibilities["a"], [Incompatibility<PackageReference>("a^1.0.0", "¬b^1.0.0", cause: .dependency(package: "a"))])
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
}
