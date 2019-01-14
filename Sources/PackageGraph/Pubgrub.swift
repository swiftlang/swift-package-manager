/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Utility.Version
import Basic
import struct PackageModel.PackageReference

/// A term represents a statement about a package that may be true or false.
struct Term<Identifier: PackageContainerIdentifier>: Equatable, Hashable {
    typealias Requirement = PackageContainerConstraint<Identifier>.Requirement

    let package: Identifier
    let requirement: Requirement
    let isPositive: Bool

    init(package: Identifier, requirement: Requirement, isPositive: Bool) {
        self.package = package
        self.requirement = requirement
        self.isPositive = isPositive
    }

    init(_ package: Identifier, _ requirement: Requirement) {
        self.init(package: package, requirement: requirement, isPositive: true)
    }

    /// Create a new negative term.
    init(not package: Identifier, _ requirement: Requirement) {
        self.init(package: package, requirement: requirement, isPositive: false)
    }

    /// The same term with an inversed `isPositive` value.
    var inverse: Term {
        return Term(
            package: package,
            requirement: requirement,
            isPositive: !isPositive)
    }

    /// Check if this term satisfies another term, e.g. if `self` is true,
    /// `other` must also be true.
    func satisfies(_ other: Term) -> Bool {
        // TODO: This probably makes more sense as isSatisfied(by:) instead.
        guard self.package == other.package else { return false }

        let samePolarity = self.isPositive == other.isPositive

        switch (self.requirement, other.requirement) {
        case (.versionSet(let lhs), .versionSet(let rhs)):
            switch (lhs, rhs) {
            case (.empty, _), (_, .empty):
                return !samePolarity
            case (.any, _), (_, .any):
                return samePolarity
            case (.exact(let lhs), .exact(let rhs)):
                return lhs == rhs && samePolarity
            case (.exact(let lhs), .range(let rhs)),
                 (.range(let rhs), .exact(let lhs)):
                return (rhs.contains(version: lhs) && samePolarity)
                    || (!rhs.contains(version: lhs) && !samePolarity)
            case (.range(let lhs), .range(let rhs)):
                let equalsOrContains = lhs == rhs || (lhs.contains(rhs) || rhs.contains(lhs))
                return (equalsOrContains && samePolarity) || (!equalsOrContains && !samePolarity)
            }
        case (.revision(let lhs), .revision(let rhs)):
            return lhs == rhs
        case (.unversioned, .unversioned):
            return false
        default:
            return false
        }
    }

    func isSatisfied(by other: Version) -> Bool {
        // TODO: isPositive plays a role here as well, doesn't it?
        switch requirement {
        case .versionSet(.exact(let version)):
            return version == other
        case .versionSet(.range(let range)):
            return range.contains(version: other)
        case .versionSet(.any):
            return true
        default:
            return false
        }
    }

    /// Create an intersection with another term.
    func intersect(with other: Term) -> Term? {
        guard self.package == other.package else { return nil }
        return intersect(withRequirement: other.requirement, andPolarity: other.isPositive)
    }

    /// Create an intersection with a requirement and polarity returning a new
    /// term which represents the version constraints allowed by both the current
    /// and given term.
    /// Returns `nil` if an intersection is not possible (possibly due to being
    /// constrained on branches, revisions, local, etc. or entirely different packages).
    func intersect(withRequirement requirement: Requirement, andPolarity isPositive: Bool) -> Term? {
        // TODO: This needs more tests.
        guard case .versionSet(let lhs) = self.requirement, case .versionSet(let rhs) = requirement else { return nil }

        let samePolarity = self.isPositive == isPositive

        if samePolarity {
            if case .range(let lhs) = lhs, case .range(let rhs) = rhs {
                let bothNegative = !self.isPositive && !isPositive
                if bothNegative {
                    guard lhs.overlaps(rhs) || rhs.overlaps(lhs) else { return nil }

                    let lower = min(lhs.lowerBound, rhs.lowerBound)
                    let upper = max(lhs.upperBound, rhs.upperBound)
                    return self.with(.versionSet(.range(lower..<upper)))
                }
            }

            let intersection = lhs.intersection(rhs)
            return Term(package, .versionSet(intersection))
        } else {
            switch (lhs, rhs) {
            case (.exact(let lhs), .exact(let rhs)):
                return lhs == rhs ? self : nil
            case (.exact(let exact), .range(let range)), (.range(let range), .exact(let exact)):
                if range.contains(version: exact) {
                    return self.with(.versionSet(.range(range.lowerBound..<exact)))
                }
                return nil
            case (.range(let lhs), .range(let rhs)):
                guard lhs.overlaps(rhs) || rhs.overlaps(lhs) else { return nil }
                var lower: Range<Version>.Bound
                var upper: Range<Version>.Bound
                if lhs.upperBound > rhs.upperBound {
                    lower = min(rhs.upperBound, lhs.upperBound)
                    upper = max(rhs.upperBound, lhs.upperBound)
                } else {
                    lower = min(lhs.lowerBound, rhs.lowerBound)
                    upper = max(lhs.lowerBound, rhs.lowerBound)
                }
                return self.with(.versionSet(.range(lower..<upper)))
            default:
                // This covers any combinations including .empty or .any.
                return nil
            }
        }
    }

    func difference(with other: Term) -> Term? {
        return self.intersect(with: other.inverse)
    }

    private func with(_ requirement: Requirement) -> Term {
        return Term(
            package: self.package,
            requirement: requirement,
            isPositive: self.isPositive)
    }

    /// Verify if the term fulfills all requirements to be a valid choice for
    /// making a decision in the given partial solution.
    /// - There has to exist a positive derivation for it.
    /// - There has to be no decision for it.
    /// - The package version has to match all assignments.
    func isValidDecision(for solution: PartialSolution<Identifier>) -> Bool {
        for assignment in solution.assignments where assignment.term.package == package {
            assert(!assignment.isDecision, "Expected assignment to be a derivation.")
            guard satisfies(assignment.term) else { return false }
        }
        return true
    }
}

extension Term: CustomStringConvertible {
    var description: String {
        var pkg = "\(package)"
        if let pkgRef = package as? PackageReference {
            pkg = pkgRef.identity
        }

        var req = ""
        switch requirement {
        case .unversioned:
            req = "unversioned"
        case .revision(let rev):
            req = rev
        case .versionSet(let vs):
            switch vs {
            case .any:
                req = "*"
            case .empty:
                req = "()"
            case .exact(let v):
                req = v.description
            case .range(let range):
                req = range.description
            }
        }

        if !isPositive {
            return "¬\(pkg) \(req)"
        }
        return "\(pkg) \(req)"
    }
}

private extension Range where Bound == Version {
    func contains(_ other: Range<Version>) -> Bool {
        return contains(version: other.lowerBound) &&
            contains(version: other.upperBound)
    }
}

/// A set of terms that are incompatible with each other and can therefore not
/// all be true at the same time. In dependency resolution, these are derived
/// from version requirements and when running into unresolvable situations.
public struct Incompatibility<Identifier: PackageContainerIdentifier>: Equatable, Hashable {
    let terms: Set<Term<Identifier>>
    let cause: Cause<Identifier>

    init(_ terms: Term<Identifier>..., cause: Cause<Identifier> = .root) {
        self.init(Set(terms), cause: cause)
    }

    // This is only used in the initializer below.
    private struct PackageAndPolarity: Hashable {
        let package: Identifier
        let isPositive: Bool

        init(_ term: Term<Identifier>) {
            self.package = term.package
            self.isPositive = term.isPositive
        }
    }

    init(_ terms: Set<Term<Identifier>>, cause: Cause<Identifier>) {
        assert(terms.count > 0, "An incompatibility must contain at least one term.")

        // Normalize terms so that at most one term refers to one package/polarity
        // combination. E.g. we don't want both a^1.0.0 and a^1.5.0 to be terms
        // in the same incompatibility, but have these combined by intersecting
        // their version requirements to a^1.5.0.

        typealias Requirement = PackageContainerConstraint<Identifier>.Requirement
        let intersectedPackages = terms.reduce(into: [PackageAndPolarity: Requirement]()) { res, term in
            let pap = PackageAndPolarity(term)
            let previous = res[pap, default: term.requirement]
            let intersection = term.intersect(withRequirement: previous, andPolarity: term.isPositive)
            return res[pap] = intersection!.requirement
        }

        let terms = intersectedPackages.keys.map { pap -> Term<Identifier> in
            let requirement = intersectedPackages[pap]!
            return Term(package: pap.package, requirement: requirement, isPositive: pap.isPositive)
        }

        self.terms = Set(terms)
        self.cause = cause
    }
}

extension Incompatibility: CustomStringConvertible {
    public var description: String {
        let terms = self.terms
            .map(String.init)
            .joined(separator: ", ")
        return "{\(terms)}"
    }
}

extension Incompatibility {
    /// Every incompatibility has a cause to explain its presence in the
    /// derivation graph. Only the root incompatibility uses `.root`. All other
    /// incompatibilities are either obtained from dependency constraints,
    /// decided upon in decision making or derived during unit propagation or
    /// conflict resolution.
    /// Using this information we can build up a derivation graph by following
    /// the tree of causes. All leaf nodes are external dependencies and all
    /// internal nodes are derived incompatibilities.
    ///
    /// An example graph could look like this:
    /// ```
    /// ┌────────────────────────────┐ ┌────────────────────────────┐
    /// │{foo ^1.0.0, not bar ^2.0.0}│ │{bar ^2.0.0, not baz ^3.0.0}│
    /// └─────────────┬──────────────┘ └──────────────┬─────────────┘
    ///               │      ┌────────────────────────┘
    ///               ▼      ▼
    /// ┌─────────────┴──────┴───────┐ ┌────────────────────────────┐
    /// │{foo ^1.0.0, not baz ^3.0.0}│ │{root 1.0.0, not foo ^1.0.0}│
    /// └─────────────┬──────────────┘ └──────────────┬─────────────┘
    ///               │   ┌───────────────────────────┘
    ///               ▼   ▼
    ///         ┌─────┴───┴──┐
    ///         │{root 1.0.0}│
    ///         └────────────┘
    /// ```
    indirect enum Cause<Identifier: PackageContainerIdentifier>: Equatable, Hashable {
        /// represents the root incompatibility
        case root
        /// represents a package's dependency
        case dependency(package: Identifier)
        /// represents an incompatibility derived from two others during
        /// conflict resolution
        case conflict(conflict: Incompatibility, other: Incompatibility)
        // TODO: Figure out what other cases should be represented here.
        // - SDK requirements
        // - no available versions
        // - package not found

        var isConflict: Bool {
            if case .conflict = self {
                return true
            }
            return false
        }

        /// Returns whether this cause can be represented in a single line of the
        /// error output.
        var isSingleLine: Bool {
            guard case .conflict(let lhs, let rhs) = self else {
                // TODO: Sure?
                return false
            }
            if case .conflict = lhs.cause, case .conflict = rhs.cause {
                return false
            }
            return true
        }
    }
}

/// An assignment that is either decided upon during decision making or derived
/// from previously known incompatibilities during unit propagation.
///
/// All assignments store a term (a package identifier and a version
/// requirement) and a decision level, which represents the number of decisions
/// at or before it in the partial solution that caused it to be derived. This
/// is later used during conflict resolution to figure out how far back to jump
/// when a conflict is found.
struct Assignment<Identifier: PackageContainerIdentifier>: Equatable {
    let term: Term<Identifier>
    let decisionLevel: Int
    let cause: Incompatibility<Identifier>?
    let isDecision: Bool

    private init(
        term: Term<Identifier>,
        decisionLevel: Int,
        cause: Incompatibility<Identifier>?,
        isDecision: Bool
    ) {
        self.term = term
        self.decisionLevel = decisionLevel
        self.cause = cause
        self.isDecision = isDecision
    }

    /// An assignment made during decision making.
    static func decision(_ term: Term<Identifier>, decisionLevel: Int) -> Assignment {
        assert(term.requirement.isExact, "Cannot create a decision assignment with a non-exact version selection.")

        return self.init(
            term: term,
            decisionLevel: decisionLevel,
            cause: nil,
            isDecision: true)
    }

    /// An assignment derived from previously known incompatibilities during
    /// unit propagation.
    static func derivation(
        _ term: Term<Identifier>,
        cause: Incompatibility<Identifier>,
        decisionLevel: Int) -> Assignment {
        return self.init(
            term: term,
            decisionLevel: decisionLevel,
            cause: cause,
            isDecision: false)
    }
}

/// The partial solution is a constantly updated solution used throughout the
/// dependency resolution process, tracking know assignments.
final class PartialSolution<Identifier: PackageContainerIdentifier> {
    var assignments: [Assignment<Identifier>]

    /// The current decision level.
    var decisionLevel: Int {
        return assignments.filter { $0.isDecision }.count
    }

    init(assignments: [Assignment<Identifier>] = []) {
        self.assignments = assignments
    }

    /// The intersection of all positive assignments for each package, minus any
    /// negative assignments that refer to that package.
    var positive: [Identifier: Term<Identifier>] {
        var values: [Identifier: Term<Identifier>] = [:]
        for val in assignments {
            let term = values[val.term.package]

            if val.term.isPositive {
                values[val.term.package] = term != nil ? term!.intersect(with: val.term) : val.term
            } else {
                values[val.term.package] = term != nil ? term!.difference(with: val.term) : val.term
            }
        }
        return values
    }

    /// A list of all packages that have been assigned, but are not yet satisfied.
    var undecided: [Term<Identifier>] {
        let decisionTerms = assignments
            .filter { $0.isDecision }
            .map { $0.term }
        return positive.values.filter { !decisionTerms.contains($0) }
    }

    /// Create a new derivation assignment and add it to the partial solution's
    /// list of known assignments.
    func derive(_ term: Term<Identifier>, cause: Incompatibility<Identifier>) {
        let derivation = Assignment.derivation(term, cause: cause, decisionLevel: decisionLevel)
        self.assignments.append(derivation)
    }

    /// Create a new decision assignment and add it to the partial solution's
    /// list of known assignments.
    func decide(_ package: Identifier, atExactVersion version: Version) {
        let term = Term(package, .versionSet(.exact(version)))
        let decision = Assignment.decision(term, decisionLevel: decisionLevel)
        self.assignments.append(decision)
    }

    /// Returns how much a given incompatibility is satisfied by assignments in
    /// this solution.
    ///
    /// Three states are possible:
    /// - Satisfied: The entire incompatibility is satisfied.
    /// - Almost Satisfied: All but one term are satisfied.
    /// - Unsatisfied: At least two terms are unsatisfied.
    func satisfies(_ incompatibility: Incompatibility<Identifier>) -> Satisfaction<Identifier> {
        return arraySatisfies(self.assignments, incompatibility: incompatibility)
    }

    /// Find a pair of assignments, a satisfier and a previous satisfier, for
    /// which the partial solution satisfies a given incompatibility up to and
    /// including the satisfier. The previous satisfier represents the first
    /// assignment in the partial solution *before* the satisfier, for which
    /// the partial solution also satisfies the given incompatibility if the
    /// satisfier is also included.
    ///
    /// To summarize, assuming at least assignment A1, A2 and A4 are needed to
    /// satisfy the assignment, (previous: A2, satisfier: A4) will be returned.
    ///
    /// In the case that the satisfier alone does not satisfy the
    /// incompatibility, it is possible that `previous` and `satisifer` refer
    /// to the same assignment.
    func earliestSatisfiers(
        for incompat: Incompatibility<Identifier>
    ) -> (previous: Assignment<Identifier>?, satisfier: Assignment<Identifier>?) {

        var firstSatisfier: Assignment<Identifier>?
        for idx in assignments.indices {
            let slice = assignments[...idx]
            if arraySatisfies(Array(slice), incompatibility: incompat) == .satisfied {
                firstSatisfier = assignments[idx]
                break
            }
        }

        guard let satisfier = firstSatisfier else {
            // The incompatibility is not (yet) satisfied by this solution's
            // list of assignments.
            return (nil, nil)
        }

        var previous: Assignment<Identifier>?
        for idx in assignments.indices {
            let slice = assignments[...idx] + [satisfier]
            if arraySatisfies(Array(slice), incompatibility: incompat) == .satisfied {
                previous = assignments[idx]
                break
            }
        }

        return (previous, satisfier)
    }

    /// Backtrack to a specific decision level by dropping all assignments with
    /// a decision level which is greater.
    func backtrack(toDecisionLevel decisionLevel: Int) {
        assignments.removeAll { $0.decisionLevel > decisionLevel }
    }

    /// Create an intersection of the versions of all assignments referring to
    /// a given package.
    /// - Returns: nil if no assignments exist or intersection of versions is
    ///            invalid.
    func versionIntersection(for package: Identifier) -> Term<Identifier>? {
        let packageAssignments = assignments.filter { $0.term.package == package }
        let firstTerm = packageAssignments.first?.term
        guard let intersection = packageAssignments.reduce(firstTerm, { result, assignment in
                guard let res = result?.intersect(with: assignment.term) else {
                    return nil
                }
                return res
            })
            else {
                return nil
        }
        return intersection
    }
}

fileprivate func arraySatisfies<Identifier: PackageContainerIdentifier>(
    _ array: [Assignment<Identifier>], incompatibility: Incompatibility<Identifier>
) -> Satisfaction<Identifier> {
    guard array.count > 0 else { return .unsatisfied }

    // Gather all terms which are satisfied by the assignments in the current solution.
    let satisfiedTerms = incompatibility.terms.filter { term in
        array.contains(where: { assignment in
            assignment.term.satisfies(term)
        })
    }

    switch satisfiedTerms.count {
    case incompatibility.terms.count:
        return .satisfied
    case incompatibility.terms.count - 1:
        let unsatisfied = incompatibility.terms.first { !satisfiedTerms.contains($0) }
        return .almostSatisfied(except: unsatisfied!)
    default:
        return .unsatisfied
    }
}

enum Satisfaction<Identifier: PackageContainerIdentifier>: Equatable {
    case satisfied
    case almostSatisfied(except: Term<Identifier>)
    case unsatisfied
}

/// A step the resolver takes to advance its progress, e.g. deriving a new assignment
/// or creating a new incompatibility based on a package's dependencies.
public struct TraceStep {
    /// The traced value, e.g. an incompatibility or term.
    public let value: Traceable
    /// How this value came to be.
    public let type: StepType
    /// Where this value was created.
    public let location: Location
    /// A previous step that caused this step.
    public let cause: String?
    /// The solution's current decision level.
    public let decisionLevel: Int

    /// A step can either store an incompatibility or a decided or derived
    /// assignment's term.
    public enum StepType: String {
        case incompatibility
        case decision
        case derivation
    }


    /// The location a step is created at.
    public enum Location: String {
        case topLevel = "top level"
        case unitPropagation = "unit propagation"
        case decisionMaking = "decision making"
        case conflictResolution = "conflict resolution"
    }
}

public protocol Traceable: CustomStringConvertible {}
extension Incompatibility: Traceable {}
extension Term: Traceable {}

/// The solver that is able to transitively resolve a set of package constraints
/// specified by a root package.
public final class PubgrubDependencyResolver<
    P: PackageContainerProvider,
    D: DependencyResolverDelegate
> where P.Container.Identifier == D.Identifier {
    public typealias Provider = P
    public typealias Delegate = D
    public typealias Container = Provider.Container
    public typealias Identifier = Container.Identifier
    public typealias Binding = (container: Identifier, binding: BoundVersion)

    /// The type of the constraints the resolver operates on.
    ///
    /// Technically this is a container constraint, but that is currently the
    /// only kind of constraints we operate on.
    public typealias Constraint = PackageContainerConstraint<Identifier>

    /// The current best guess for a solution satisfying all requirements.
    var solution = PartialSolution<Identifier>()

    /// A collection of all known incompatibilities matched to the packages they
    /// refer to. This means an incompatibility can occur several times.
    var incompatibilities: [Identifier: [Incompatibility<Identifier>]] = [:]

    /// Find all incompatibilities containing a positive term for a given package.
    func positiveIncompatibilities(for package: Identifier) -> [Incompatibility<Identifier>]? {
        guard let all = incompatibilities[package] else {
            return nil
        }
        return all.filter {
            $0.terms.first { $0.package == package }!.isPositive
        }
    }

    /// The root package reference.
    var root: Identifier?

    /// The container provider used to load package containers.
    let provider: Provider

    /// The resolver's delegate.
    let delegate: Delegate?

    /// A subset of packages used during unit propagation.
    var changed: Set<Identifier> = []

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    func trace(
        value: Traceable,
        type: TraceStep.StepType,
        location: TraceStep.Location,
        cause: String?
        ) {
        delegate?.trace(TraceStep(value: value,
                                  type: type,
                                  location: location,
                                  cause: cause,
                                  decisionLevel: solution.decisionLevel))
    }

    func decide(_ package: Identifier, version: Version, location: TraceStep.Location) {
        let term = Term(package, .versionSet(.exact(version)))
        trace(value: term, type: .decision, location: location, cause: nil)
        solution.decide(package, atExactVersion: version)
    }

    func derive(_ term: Term<Identifier>, cause: Incompatibility<Identifier>, location: TraceStep.Location) {
        trace(value: term, type: .derivation, location: location, cause: nil)
        solution.derive(term, cause: cause)
    }

    public init(
        _ provider: Provider,
        _ delegate: Delegate? = nil,
        skipUpdate: Bool = false
        ) {
        self.provider = provider
        self.delegate = delegate
        self.skipUpdate = skipUpdate
    }

    /// Add a new incompatibility to the list of known incompatibilities.
    func add(_ incompatibility: Incompatibility<Identifier>, location: TraceStep.Location) {
        trace(value: incompatibility, type: .incompatibility, location: location, cause: nil)
        for package in incompatibility.terms.map({ $0.package }) {
            if incompatibilities[package] != nil {
                if !incompatibilities[package]!.contains(incompatibility) {
                    incompatibilities[package]!.append(incompatibility)
                }
            } else {
                incompatibilities[package] = [incompatibility]
            }
        }
    }

    public typealias Result = DependencyResolver<P, D>.Result

    // TODO: This should be the actual (and probably only) entrypoint to version solving.
    /// Run the resolution algorithm on a root package finding a valid assignment of versions.
    public func solve(root: Identifier, pins: [Constraint]) -> Result {
        self.root = root
        do {
            return try .success(solve(constraints: [], pins: pins))
        } catch {
            return .error(error)
        }
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    public func solve(dependencies: [Constraint], pins: [Constraint]) -> Result {
        guard let root = dependencies.first?.identifier else {
            fatalError("expected a root package")
        }
        self.root = root
        return solve(root: root, pins: pins)
    }

    public enum Error: Swift.Error {
        case unresolvable(Incompatibility<Identifier>)
    }

    /// Find a set of dependencies that fit the given constraints. If dependency
    /// resolution is unable to provide a result, an error is thrown.
    /// - Warning: It is expected that the root package reference has been set
    ///            before this is called.
    public func solve(
        constraints: [Constraint], pins: [Constraint]
    ) throws -> [(container: Identifier, binding: BoundVersion)] {
        // TODO: Handle pins
        guard let root = self.root else {
            fatalError("Expected resolver root reference to be set.")
        }

        // Handle root, e.g. add dependencies and root decision.
        decide(root, version: "1.0.0", location: .topLevel)

        let rootContainer = try getContainer(for: self.root!)
        for dependency in try rootContainer.getUnversionedDependencies() {
            let incompatibility = Incompatibility(
                Term(root, .versionSet(.exact("1.0.0"))),
                Term(not: dependency.identifier, dependency.requirement), cause: .root)
            add(incompatibility, location: .topLevel)
        }

        var next: Identifier? = root
        while let nxt = next {
            if let conflict = propagate(nxt) {
                guard let rootCause = resolve(conflict: conflict) else {
                    throw Error.unresolvable(conflict)
                }
                changed.removeAll()

                guard case .almostSatisfied(except: let term) = solution.satisfies(rootCause) else {
                    fatalError("""
                        Expected root cause [\(rootCause)] to almost satisfy the \
                        current partial solution:
                        \(solution)
                        """)
                }
                changed.insert(term.package)
            }

            // If decision making determines that no more decisions are to be
            // made, it returns nil to signal that version solving is done.
            next = try makeDecision()
        }

        let decisions = solution.assignments.filter { $0.isDecision }
        let finalAssignments: [(container: Identifier, binding: BoundVersion)] = decisions.map { assignment in
            var boundVersion: BoundVersion
            switch assignment.term.requirement {
            case .versionSet(.exact(let version)):
                boundVersion = .version(version)
            case .revision(let rev):
                boundVersion = .revision(rev)
            case .versionSet(.range(_)):
                // FIXME: A new requirement type that makes having a range here impossible feels like the correct thing to do.
                fatalError("Solution should not contain version ranges.")
            case .unversioned, .versionSet(.any):
                boundVersion = .unversioned
            case .versionSet(.empty):
                fatalError("Solution should not contain empty versionSet requirement.")
            }

            return (assignment.term.package, boundVersion)
        }

        return finalAssignments.filter { $0.container != root }
    }

    /// Perform unit propagation to derive new assignments based on the current
    /// partial solution.
    /// If a conflict is found, the conflicting incompatibility is returned to
    /// resolve the conflict on.
    func propagate(_ package: Identifier) -> Incompatibility<Identifier>? {
        changed.insert(package)
        while !changed.isEmpty {
            let package = changed.removeFirst()
            // According to the experience of pub developers, conflict
            // resolution produces more general incompatibilities later on
            // making it advantageous to check those first.
            for incompatibility in positiveIncompatibilities(for: package)?.reversed() ?? [] {
                switch solution.satisfies(incompatibility) {
                case .unsatisfied:
                    break
                case .satisfied:
                    return incompatibility
                case .almostSatisfied(except: let term):
                    derive(term.inverse, cause: incompatibility, location: .unitPropagation)
                }
            }
        }

        return nil
    }

    /// Perform conflict resolution to backtrack to the root cause of a
    /// satisfied incompatibility and create a new incompatibility that blocks
    /// off the search path that led there.
    /// Returns nil if version solving is unsuccessful.
    func resolve(conflict: Incompatibility<Identifier>) -> Incompatibility<Identifier>? {
        var incompatibility = conflict

        // As long as the incompatibility doesn't specify that version solving
        // has failed entirely...
        while !isCompleteFailure(incompatibility) {
            // Find the earliest assignment so that `incompatibility` is
            // satisfied by the partial solution up to and including it.
            // ↳ `satisfier`
            // Also find the earliest assignment before `satisfier` which
            // satisfies `incompatibility` up to and including it + `satisfier`.
            // ↳ `previous`
            let (previous, possibleSatisfier) = solution.earliestSatisfiers(for: incompatibility)
            guard let satisfier = possibleSatisfier else { break }

            // `term` is incompatibility's term referring to the same term as
            // satisfier.
            let term = incompatibility.terms.first { $0.package == satisfier.term.package }

            // Decision level is where the root package was selected. According
            // to PubGrub documentation it's also fine to fall back to 0, but
            // choosing 1 tends to produce better error output.
            let previousSatisfierLevel = previous?.decisionLevel ?? 1

            if satisfier.isDecision || previousSatisfierLevel != satisfier.decisionLevel {
                if incompatibility != conflict {
                    add(incompatibility, location: .conflictResolution)
                }
                solution.backtrack(toDecisionLevel: previousSatisfierLevel)
                return incompatibility
            } else {
                // `priorCauseTerms` should be a union of the terms in
                // `incompatibility` and the terms in `satisfier`'s cause, minus
                // the terms referring to `satisfier`'s package.
                var priorCauseTerms = incompatibility.terms.union(satisfier.cause?.terms ?? [])
                priorCauseTerms = priorCauseTerms.filter { $0.package != satisfier.term.package }

                if !satisfier.term.satisfies(term!) {
                    // add ¬(satisfier \ term) to priorCauseTerms
                    if satisfier.term != term {
                        priorCauseTerms.insert(satisfier.term.inverse)
                    }
                }

                incompatibility = Incompatibility(
                    priorCauseTerms,
                    cause: .conflict(conflict: conflict, other: incompatibility)
                )
            }
        }

        // TODO: Report error with `incompatibility` as the root incompatibility.
        return nil
    }

    /// Does a given incompatibility specify that version solving has entirely
    /// failed? E.g. is this incompatibility either empty or only for the root
    /// package?
    private func isCompleteFailure(_ incompatibility: Incompatibility<Identifier>) -> Bool {
        guard !incompatibility.terms.isEmpty else { return true }
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.package == root
    }

    func makeDecision() throws -> Identifier? {
        // If there are no more undecided terms, version solving is complete.
        guard !solution.undecided.isEmpty else { return nil }

        // Select a possible candidate from all undecided assignments, making
        // sure it only exists as a positive derivation and no decision.
        for candidate in solution.undecided where candidate.isValidDecision(for: solution) {
            guard let term = solution.versionIntersection(for: candidate.package) else {
                fatalError("failed to create version intersection for \(candidate.package)")
            }

            // select an actual `version` of `candidate` that matches `term`
            let container = try! getContainer(for: term.package)
            let latestVersion = Array(container.versions { term.isSatisfied(by: $0) }).first

            // if no such version exists
            //    add incompatibility {term} to incompatibilities and return package's name
            //    this avoids this range of versions in the future
            guard let version = latestVersion else {
                // FIXME: Use correct cause
                let incompatibility = Incompatibility(term, cause: .root)
                add(incompatibility, location: .decisionMaking)
                continue
            }

            // add each incompatibility from version's dependencies to incompatibilities
            try container.getDependencies(at: version)
                .map { dep -> Incompatibility<Identifier> in
                    let terms: Set = [
                        Term(candidate.package, .versionSet(.exact(version))),
                        Term(not: dep.identifier, dep.requirement)
                    ]
                    return Incompatibility(terms, cause: .dependency(package: candidate.package))
                }
                .forEach { add($0, location: .decisionMaking) }

            // add `version` to partial solution as a decision, unless this would produce a conflict in any of the new incompatibilities
            // FIXME: Use correct cause
            let _ = Incompatibility(Term(candidate.package, .versionSet(.exact(version))), cause: .root)
            //            if case .satisfied = solution.satisfies(candidateIncompat) {
            //                continue // TODO: is this correct?
            //            }
            decide(candidate.package, version: version, location: .decisionMaking)

            return candidate.package
        }

        return nil
    }

    // MARK: - Error Reporting

    private var derivations: [Incompatibility<Identifier>: Int] = [:]

    func reportError(for incompatibility: Incompatibility<Identifier>) -> String {
        /// Populate `derivations`.
        func countDerivations(_ i: Incompatibility<Identifier>) {
            derivations[i, default: 0] += 1
            if case .conflict(let lhs, let rhs) = i.cause {
                countDerivations(lhs)
                countDerivations(rhs)
            }
        }

        countDerivations(incompatibility)

        let stream = BufferedOutputByteStream()
        visit(incompatibility, stream)

        return stream.bytes.asString!
    }

    private func visit(
        _ incompatibility: Incompatibility<Identifier>,
        _ stream: BufferedOutputByteStream,
        isConclusion: Bool = false
    ) {

        let isNumbered = isConclusion || derivations[incompatibility]! > 1

        guard case .conflict(let lhs, let rhs) = incompatibility.cause else {
            // TODO: Do nothing else here?
            return
        }

        switch (lhs.cause, rhs.cause) {
        case (.conflict, .conflict):
            let lhsLine = lineNumbers[lhs]
            let rhsLine = lineNumbers[rhs]

            switch (lhsLine, rhsLine) {
            case (.some(let lhsLine), .some(let rhsLine)):
                write(incompatibility,
                      message: "Because \(lhs) (\(lhsLine)) and \(rhs) (\(rhsLine), \(incompatibility).",
                      isNumbered: isNumbered,
                      toStream: stream)
            case (.some(let lhsLine), .none):
                visit(incompatibility, stream)
                write(incompatibility,
                      message: "And because \(lhs) (\(lhsLine)), \(incompatibility).",
                      isNumbered: isNumbered,
                      toStream: stream)
            case (.none, .some(let rhsLine)):
                visit(incompatibility, stream)
                write(incompatibility,
                      message: "And because \(rhs) (\(rhsLine)), \(incompatibility).",
                      isNumbered: isNumbered,
                      toStream: stream)
            case (.none, .none):
                let singleLineConflict = lhs.cause.isSingleLine
                let singleLineOther = rhs.cause.isSingleLine

                if singleLineOther || singleLineConflict {
                    let simple = singleLineOther ? lhs : rhs
                    let complex = singleLineOther ? rhs : lhs
                    visit(simple, stream)
                    visit(complex, stream)
                    write(incompatibility,
                        message: "Thus, \(incompatibility)",
                        isNumbered: isNumbered,
                        toStream: stream)
                } else {
                    visit(lhs, stream, isConclusion: true)
                    write(incompatibility,
                        message: "\n",
                        isNumbered: isNumbered,
                        toStream: stream)

                    visit(rhs, stream)
                    // TODO: lhsLine will always be nil here...
                    write(incompatibility,
                        message: "And because \(lhs) (\(lhsLine ?? -1)), \(incompatibility).",
                        isNumbered: isNumbered,
                        toStream: stream)
                }

            }
        case (.conflict, _), (_, .conflict):
            var derived: Incompatibility<Identifier>
            var external: Incompatibility<Identifier>
            if case .conflict = lhs.cause {
                derived = lhs
                external = rhs
            } else {
                derived = rhs
                external = lhs
            }

            if let derivedLine = lineNumbers[derived] {
                write(incompatibility,
                    message: "Because \(external) and \(derived) (\(derivedLine)), \(incompatibility).",
                    isNumbered: isNumbered,
                    toStream: stream)
            } else if derivations[incompatibility]! <= 1 {
                guard case .conflict(let lhs, let rhs) = derived.cause else {
                    // FIXME
                    fatalError("unexpected non-conflict")
                }
                let collapsedDerived = lhs.cause.isConflict ? rhs : lhs
                let collapsedExternal = lhs.cause.isConflict ? rhs : lhs
                visit(collapsedDerived, stream)
                write(incompatibility,
                    message: "And because \(collapsedExternal) and \(external), \(incompatibility).",
                    isNumbered: isNumbered,
                    toStream: stream)
            } else {
                visit(derived, stream)
                write(incompatibility,
                    message: "And because \(external), \(incompatibility).",
                    isNumbered: isNumbered,
                    toStream: stream)
            }
        default:
            write(incompatibility,
                message: "Because \(lhs) and \(rhs), \(incompatibility).",
                isNumbered: isNumbered,
                toStream: stream)
        }
    }

    private var lineNumbers: [Incompatibility<Identifier>: Int] = [:]

    /// Write a given output message to a stream. The message should describe
    /// the incompatibility and how it as derived. If `isNumbered` is true, a
    /// line number will be assigned to this incompatibility so that it can be
    /// referred to again.
    private func write(
        _ i: Incompatibility<Identifier>,
        message: String,
        isNumbered: Bool,
        toStream stream: BufferedOutputByteStream
    ) {
        if isNumbered {
            let number = lineNumbers.count + 1
            lineNumbers[i] = number
            // TODO: Handle `number`
            stream <<< message
        } else {
            stream <<< message
        }
    }

    // MARK: - Container Management

    /// Condition for container management structures.
    private let fetchCondition = Condition()

    /// The list of fetched containers.
    private var _fetchedContainers: [Identifier: Basic.Result<Container, AnyError>] = [:]

    /// The set of containers requested so far.
    private var _prefetchingContainers: Set<Identifier> = []

    /// Get the container for the given identifier, loading it if necessary.
    fileprivate func getContainer(for identifier: Identifier) throws -> Container {
        return try fetchCondition.whileLocked {
            // Return the cached container, if available.
            if let container = _fetchedContainers[identifier] {
                return try container.dematerialize()
            }

            // If this container is being prefetched, wait for that to complete.
            while _prefetchingContainers.contains(identifier) {
                fetchCondition.wait()
            }

            // The container may now be available in our cache if it was prefetched.
            if let container = _fetchedContainers[identifier] {
                return try container.dematerialize()
            }

            // Otherwise, fetch the container synchronously.
            let container = try await { provider.getContainer(for: identifier, skipUpdate: skipUpdate, completion: $0) }
            self._fetchedContainers[identifier] = Basic.Result(container)
            return container
        }
    }
}
