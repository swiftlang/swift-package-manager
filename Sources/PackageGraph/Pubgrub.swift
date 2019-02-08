/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct SPMUtility.Version
import Basic
import struct PackageModel.PackageReference

/// A term represents a statement about a package that may be true or false.
public struct Term<Identifier: PackageContainerIdentifier>: Equatable, Hashable {
    typealias Requirement = PackageRequirement

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
        let isSatisfied: Bool
        switch requirement {
        case .versionSet(.exact(let version)):
            isSatisfied = version == other
        case .versionSet(.range(let range)):
            isSatisfied = range.contains(version: other)
        case .versionSet(.any):
            isSatisfied = true
        default:
            isSatisfied = false
        }

        return isPositive ? isSatisfied : !isSatisfied
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
                let positive = self.isPositive ? lhs : rhs
                let negative = self.isPositive ? rhs : lhs
                let positiveTerm = Term(self.package, self.requirement)
                guard lhs != rhs else {
                    return nil
                }
                guard lhs.overlaps(rhs) else {
                    return positiveTerm.with(.versionSet(.range(positive)))
                }
                if positive.lowerBound < negative.lowerBound {
                    return positiveTerm.with(.versionSet(.range(positive.lowerBound..<negative.lowerBound)))
                } else {
                    return positiveTerm.with(.versionSet(.range(negative.upperBound..<positive.upperBound)))
                }
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
    public var description: String {
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
    let terms: OrderedSet<Term<Identifier>>
    let cause: Cause<Identifier>

    init(terms: OrderedSet<Term<Identifier>>, cause: Cause<Identifier>) {
        self.terms = terms
        self.cause = cause
    }

    init(_ terms: Term<Identifier>..., root: Identifier, cause: Cause<Identifier> = .root) {
        let termSet = OrderedSet(terms)
        self.init(termSet, root: root, cause: cause)
    }

    init(_ terms: OrderedSet<Term<Identifier>>, root: Identifier, cause: Cause<Identifier>) {
        assert(terms.count > 0, "An incompatibility must contain at least one term.")

        // Remove the root package from generated incompatibilities, since it will
        // always be selected.
        var terms = terms
        if terms.count > 1,
            case .conflict(conflict: _, other: _) = cause,
            terms.contains(where: { $0.isPositive && $0.package == root })
        {
            terms = OrderedSet(terms.filter { !$0.isPositive || $0.package != root })
        }

        let termsArray = Array(terms)

        // If there is only one term or two terms referring to the same package
        // we can skip the extra work of trying to normalize these.
        if termsArray.count == 1 ||
            (termsArray.count == 2 && termsArray.first?.package != termsArray.last?.package)
        {
            self.init(terms: terms, cause: cause)
            return
        }

        let normalizedTerms = normalize(terms: terms.contents)
        self.init(terms: OrderedSet(normalizedTerms), cause: cause)
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
public struct Assignment<Identifier: PackageContainerIdentifier>: Equatable {
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

extension Assignment: CustomStringConvertible {
    public var description: String {
        switch self.isDecision {
        case true:
            return "[Decision \(decisionLevel): \(term)]"
        case false:
            return "[Derivation: \(term) ← \(cause?.description ?? "-")]"
        }
    }
}

/// The partial solution is a constantly updated solution used throughout the
/// dependency resolution process, tracking know assignments.
final class PartialSolution<Identifier: PackageContainerIdentifier> {
    var root: Identifier?

    /// All known assigments.
    var assignments: [Assignment<Identifier>]

    /// All known decisions.
    var decisions: [Identifier: VersionSetSpecifier] = [:]

    /// The current decision level.
    var decisionLevel: Int {
        return decisions.count - 1
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
        decisions[package] = .exact(version)
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

        guard previous != assignments.first else {
            // this is the root assignment, if this is the previous satisfier we
            // want to return nil instead to signal to conflict resolution that
            // we've hit the root incompatibility.
            return (nil, satisfier)
        }

        return (previous, satisfier)
    }

    /// Backtrack to a specific decision level by dropping all assignments with
    /// a decision level which is greater.
    func backtrack(toDecisionLevel decisionLevel: Int) {
        var toBeRemoved: [(Int, Assignment<Identifier>)] = []

        for (idx, assignment) in zip(0..., assignments) {
            // Remove *all* derivations and decisions above the specified level.
            if !assignment.isDecision && assignment.decisionLevel >= decisionLevel {
                toBeRemoved.append((idx, assignment))
                continue
            }
            if assignment.decisionLevel > decisionLevel {
                toBeRemoved.append((idx, assignment))
            }
        }

        for (idx, remove) in toBeRemoved.reversed() {
            assignments.remove(at: idx)
            decisions.removeValue(forKey: remove.term.package)
        }
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

    /// Check if the solution contains a positive decision for a given package.
    func hasDecision(for package: Identifier) -> Bool {
        for decision in assignments where decision.isDecision {
            if decision.term.package == package && decision.term.isPositive {
                return true
            }
        }
        return false
    }

    /// Does the solution contain a decision for every derivation meaning
    /// that all necessary packages have been found?
    var isFinished: Bool {
        for derivation in assignments where !derivation.isDecision {
            guard self.hasDecision(for: derivation.term.package) else {
                return false
            }
        }
        return true
    }
}

fileprivate func arraySatisfies<Identifier: PackageContainerIdentifier>(
    _ array: [Assignment<Identifier>], incompatibility: Incompatibility<Identifier>
) -> Satisfaction<Identifier> {
    guard !array.isEmpty else {
        if incompatibility.terms.count == 1 {
            return .almostSatisfied(except: incompatibility.terms.first!)
        }
        return .unsatisfied
    }

    let normalizedTerms = normalize(terms: array.map { $0.term })

    // Gather all terms which are satisfied by the assignments in the current solution.
    let satisfiedTerms = incompatibility.terms.filter { term in
        normalizedTerms.contains(where: { assignmentTerm in
            assignmentTerm.satisfies(term)
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

/// Normalize terms so that at most one term refers to one package/polarity
/// combination. E.g. we don't want both a^1.0.0 and a^1.5.0 to be terms in the
/// same incompatibility, but have these combined by intersecting their version
/// requirements to a^1.5.0.
fileprivate func normalize<Identifier: PackageContainerIdentifier>(
    terms: [Term<Identifier>]) -> [Term<Identifier>] {
    typealias Requirement = PackageRequirement
    let dict = terms.reduce(into: [Identifier: (req: Requirement, polarity: Bool)]()) {
        res, term in
        let previous = res[term.package, default: (term.requirement, term.isPositive)]
        let intersection = term.intersect(withRequirement: previous.req,
                                          andPolarity: previous.polarity)
        assert(intersection != nil, """
            Attempting to create an incompatibility with terms for \(term.package) \
            intersecting versions \(previous) and \(term.requirement). These are \
            mutually exclusive and can't be intersected, making this incompatibility \
            irrelevant.
            """)
        return res[term.package] = (intersection!.requirement, intersection!.isPositive)
    }
    // Sorting the values for deterministic test runs.
    let sortedKeys = dict.keys.sorted(by: { lhs, rhs in
        return String(describing: lhs) < String(describing: rhs)
    })
    let newTerms = sortedKeys.map { pkg -> Term<Identifier> in
        let req = dict[pkg]!
        return Term(package: pkg, requirement: req.req, isPositive: req.polarity)
    }
    return newTerms
}

enum Satisfaction<Identifier: PackageContainerIdentifier>: Equatable {
    case satisfied
    case almostSatisfied(except: Term<Identifier>)
    case unsatisfied
}

/// A step the resolver takes to advance its progress, e.g. deriving a new assignment
/// or creating a new incompatibility based on a package's dependencies.
public struct GeneralTraceStep {
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

/// A step the resolver takes during conflict resolution.
public struct ConflictResolutionTraceStep<Identifier: PackageContainerIdentifier> {
    /// The conflicted incompatibility.
    public let incompatibility: Incompatibility<Identifier>
    public let term: Term<Identifier>
    /// The satisfying assignment.
    public let satisfier: Assignment<Identifier>
}

public enum TraceStep<Identifier: PackageContainerIdentifier> {
    case general(GeneralTraceStep)
    case conflictResolution(ConflictResolutionTraceStep<Identifier>)
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

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    func trace(
        value: Traceable,
        type: GeneralTraceStep.StepType,
        location: GeneralTraceStep.Location,
        cause: String?
        ) {
        let step = GeneralTraceStep(value: value,
                             type: type,
                             location: location,
                             cause: cause,
                             decisionLevel: solution.decisionLevel)
        delegate?.trace(.general(step))
    }

    /// Trace a conflict resolution step.
    func trace(
        incompatibility: Incompatibility<Identifier>,
        term: Term<Identifier>,
        satisfier: Assignment<Identifier>
        ) {
        let step = ConflictResolutionTraceStep(incompatibility: incompatibility,
                                               term: term,
                                               satisfier: satisfier)
        delegate?.trace(.conflictResolution(step))
    }

    func decide(_ package: Identifier, version: Version, location: GeneralTraceStep.Location) {
        let term = Term(package, .versionSet(.exact(version)))
        trace(value: term, type: .decision, location: location, cause: nil)
        solution.decide(package, atExactVersion: version)
    }

    func derive(_ term: Term<Identifier>, cause: Incompatibility<Identifier>, location: GeneralTraceStep.Location) {
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
    func add(_ incompatibility: Incompatibility<Identifier>, location: GeneralTraceStep.Location) {
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
        self.solution.root = root
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

    public enum PubgrubError: Swift.Error {
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
                Term(not: dependency.identifier, dependency.requirement),
                root: root, cause: .root)
            add(incompatibility, location: .topLevel)
        }

        do {
            try run(propagating: root)
        } catch PubgrubError.unresolvable(let conflict) {
            let description = reportError(for: conflict)
            print(description)
            return []
        } catch {
            fatalError("Unexpected error.")
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

    /// Perform unit propagation, resolving conflicts if necessary and making
    /// decisions if nothing else is left to be done.
    /// After this method returns `solution` is either populated with a list of
    /// final version assignments or an error is thrown.
    func run(propagating package: Identifier) throws {
        var changed: OrderedSet<Identifier> = []

        var next: Identifier? = root

        while let nxt = next {
            if let conflict = propagate(nxt, changed: &changed) {
                guard let rootCause = resolve(conflict: conflict) else {
                    throw PubgrubError.unresolvable(conflict)
                }

                let satisfaction = solution.satisfies(rootCause)
                guard case .almostSatisfied(except: let term) = satisfaction else {
                    fatalError("""
                        Expected root cause \(rootCause) to almost satisfy the \
                        current partial solution:
                        \(solution.assignments.map { " * \($0.description)" }.joined(separator: "\n"))\n
                        """)
                }

                changed.removeAll(keepingCapacity: false)
                changed.append(term.package)
                continue
            }

            // If the solution contains a decision for every derivation version
            // solving is finished.
            if solution.isFinished {
                return
            }

            // If decision making determines that no more decisions are to be
            // made, it returns nil to signal that version solving is done.
            next = try makeDecision()
        }
    }

    /// Perform unit propagation to derive new assignments based on the current
    /// partial solution.
    /// If a conflict is found, the conflicting incompatibility is returned to
    /// resolve the conflict on.
    func propagate(_ package: Identifier, changed: inout OrderedSet<Identifier>) -> Incompatibility<Identifier>? {
        changed.append(package)
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
            // ↳ `possibleSatisfier`
            // Also find the earliest assignment before `satisfier` which
            // satisfies `incompatibility` up to and including it + `satisfier`.
            // ↳ `previous`
            let (previous, possibleSatisfier) = solution.earliestSatisfiers(for: incompatibility)
            guard let satisfier = possibleSatisfier else { break }

            // `term` is incompatibility's term referring to the same term as satisfier.
            let term = incompatibility.terms.first { $0.package == satisfier.term.package }

            trace(incompatibility: incompatibility, term: term!, satisfier: satisfier)

            if previous == nil {
                add(incompatibility, location: .conflictResolution)
                solution.backtrack(toDecisionLevel: 0)
                return incompatibility
            }

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
                let termSet = Set(incompatibility.terms)
                let priorCauseTermsArr = Array(termSet.union(satisfier.cause?.terms ?? []))
                    .filter { $0.package != satisfier.term.package }
                var priorCauseTerms = OrderedSet(priorCauseTermsArr)

                if !satisfier.term.satisfies(term!) {
                    // add ¬(satisfier \ term) to priorCauseTerms
                    if satisfier.term != term {
                        priorCauseTerms.append(satisfier.term.inverse)
                    }
                }

                incompatibility = Incompatibility(priorCauseTerms,
                                                  root: root!,
                                                  cause: .conflict(conflict: conflict,
                                                                   other: incompatibility))
            }
        }

        // TODO: Report error with `incompatibility` as the root incompatibility.
        return nil
    }

    /// Does a given incompatibility specify that version solving has entirely
    /// failed, meaning this incompatibility is either empty or only for the root
    /// package.
    private func isCompleteFailure(_ incompatibility: Incompatibility<Identifier>) -> Bool {
        guard !incompatibility.terms.isEmpty else { return true }
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.package == root
    }

    func makeDecision() throws -> Identifier? {
        // If there are no more undecided terms, version solving is complete.
        guard !solution.undecided.isEmpty else {
            return nil
        }

        // This is set when we encounter a possible conflict below, but
        // reset at the next version. The idea is to track the case that the
        // last available version results in a conflict.
        var latestConflict: Identifier?

        // Select a possible candidate from all undecided assignments, making
        // sure it only exists as a positive derivation and no decision.
        for candidate in solution.undecided where candidate.isValidDecision(for: solution) {
            guard let term = solution.versionIntersection(for: candidate.package) else {
                fatalError("failed to create version intersection for \(candidate.package)")
            }

            let container = try! getContainer(for: term.package)

            var latestVersion: Version?
            versionSelection: for version in container.versions(filter: { term.isSatisfied(by: $0) }) {
                if latestVersion == nil { latestVersion = version }
                latestConflict = nil

                // If there is an existing single-positive-term incompatibility
                // that forbids this version, we should skip right to trying the
                // next one.
                let requirements = incompatibilities[term.package]?
                    .filter {
                        $0.terms.count == 1 &&
                        $0.terms.first?.package == term.package &&
                        $0.terms.first?.isPositive == true
                    }
                    .map {
                        $0.terms.first!.requirement
                    }

                for forbidden in requirements ?? [] {
                    switch forbidden {
                    case .versionSet(let versionSet):
                        switch versionSet {
                        case .any:
                            continue versionSelection
                        case .range(let forbidden):
                            if forbidden.contains(version: version) {
                                continue versionSelection
                            }
                        case .exact(let forbidden):
                            if forbidden == version {
                                continue versionSelection
                            }
                        case .empty:
                            break
                        }
                    default:
                        break
                    }
                }

                // Add all of this version's dependencies as incompatibilities.
                let depIncompatibilities = try container.getDependencies(at: version)
                    .map { dep -> Incompatibility<Identifier> in
                        var terms: OrderedSet<Term<Identifier>> = []
                        // If the selected version is the latest version, Pubgrub
                        // represents the term as having an unbounded upper range.
                        // We can't represent that here (currently), so we're
                        // pretending that it goes to the next nonexistent major
                        // version.
                        if version == latestVersion {
                            let nextMajor = Version(version.major + 1, 0, 0)
                            terms.append(Term(candidate.package, .versionSet(.range(version..<nextMajor))))
                            terms.append(Term(not: dep.identifier, dep.requirement))
                        } else {
                            terms.append(Term(candidate.package, .versionSet(.exact(version))))
                            terms.append(Term(not: dep.identifier, dep.requirement))
                        }
                        return Incompatibility(terms, root: root!, cause: .dependency(package: candidate.package))
                    }
                depIncompatibilities.forEach { add($0, location: .decisionMaking) }

                let tmp = PartialSolution(assignments: solution.assignments)
                tmp.decide(candidate.package, atExactVersion: version)
                // Check if this decision would result in a conflict when added.
                // If so, we try the next earlier version instead.
                #warning("Why is this depIncompatibilities and not incompatibilities[candidate.package]?")
                for incompat in depIncompatibilities {
                    if case .satisfied = tmp.satisfies(incompat) {
                        latestConflict = candidate.package
                        continue versionSelection
                    }
                }

                decide(candidate.package, version: version, location: .decisionMaking)
                return candidate.package
            }
        }

        if let conflict = latestConflict {
            return conflict
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

        return stream.bytes.description
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
