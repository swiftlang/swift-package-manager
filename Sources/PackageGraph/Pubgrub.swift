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
        return self.relation(with: other) == .subset
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

    func relation(with other: Term) -> SetRelation {
        // From: https://github.com/dart-lang/pub/blob/master/lib/src/solver/term.dart

        if self.package != other.package {
            fatalError("attempting to compute relation between different packages \(self) \(other)")
        }

        if other.isPositive {
            if self.isPositive {
                // If the second requirement contains all the elements of
                // the first requirement, then it is a subset relation.
                if other.requirement.containsAll(self.requirement) {
                    return .subset
                }

                // If second requirement contains any requirements of
                // the first, then the relation is overlapping.
                if other.requirement.containsAny(self.requirement) {
                    return .overlap
                }

                // Otherwise it is disjoint.
                return .disjoint
            } else {
                if self.requirement.containsAll(other.requirement) {
                    return .disjoint
                }
                return .overlap
            }
        } else {
            if self.isPositive {
                if !other.requirement.containsAny(self.requirement) {
                    return .subset
                }
                if other.requirement.containsAll(self.requirement) {
                    return .disjoint
                }
                return .overlap
            } else {
                if self.requirement.containsAll(other.requirement) {
                    return .subset
                }
                return .overlap
            }
        }
    }

    enum SetRelation: Equatable {
        /// The sets have nothing in common.
        case disjoint
        /// The sets have elements in common but first set is not a subset of second.
        case overlap
        /// The second set contains all elements of the first set.
        case subset
    }
}

extension PackageRequirement {
    func containsAll(_ other: PackageRequirement) -> Bool {
        switch (self, other) {
        case (.versionSet(let lhs), .versionSet(let rhs)):
            return lhs.intersection(rhs) == rhs
        default:
            fatalError("unhandled \(self), \(other)")
        }
    }

    func containsAny(_ other: PackageRequirement) -> Bool {
        switch (self, other) {
        case (.versionSet(let lhs), .versionSet(let rhs)):
            return lhs.intersection(rhs) != .empty
        default:
            fatalError("unhandled \(self), \(other)")
        }
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
    private(set) var assignments: [Assignment<Identifier>]

    /// All known decisions.
    private(set) var decisions: [Identifier: Version] = [:]

    /// The intersection of all positive assignments for each package, minus any
    /// negative assignments that refer to that package.
    private(set) var _positive: [Identifier: Term<Identifier>] = [:]

    /// Union of all negative assignments for a package.
    ///
    /// Only present if a package has no postive assignment.
    private(set) var _negative: [Identifier: Term<Identifier>] = [:]

    /// The current decision level.
    var decisionLevel: Int {
        return decisions.count - 1
    }

    init(assignments: [Assignment<Identifier>] = []) {
        self.assignments = assignments
        for assignment in assignments {
            register(assignment)
        }
    }

    /// A list of all packages that have been assigned, but are not yet satisfied.
    var undecided: [Term<Identifier>] {
        // FIXME: Should we sort this so we have a deterministic results?
        return _positive.values.filter { !decisions.keys.contains($0.package) }
    }

    /// Create a new derivation assignment and add it to the partial solution's
    /// list of known assignments.
    func derive(_ term: Term<Identifier>, cause: Incompatibility<Identifier>) {
        let derivation = Assignment.derivation(term, cause: cause, decisionLevel: decisionLevel)
        self.assignments.append(derivation)
        register(derivation)
    }

    /// Create a new decision assignment and add it to the partial solution's
    /// list of known assignments.
    func decide(_ package: Identifier, atExactVersion version: Version) {
        decisions[package] = version
        let term = Term(package, .versionSet(.exact(version)))
        let decision = Assignment.decision(term, decisionLevel: decisionLevel)
        self.assignments.append(decision)
        register(decision)
    }

    /// Populates the _positive and _negative poperties with the assignment.
    private func register(_ assignment: Assignment<Identifier>) {
        let term = assignment.term
        let pkg = term.package

        if let positive = _positive[pkg] {
            _positive[term.package] = positive.intersect(with: term)
            return
        }

        let newTerm = _negative[pkg].flatMap{ term.intersect(with: $0) } ?? term
        
        if newTerm.isPositive {
            _negative[pkg] = nil
            _positive[pkg] = newTerm
        } else {
            _negative[pkg] = newTerm
        }
    }

    /// Returns the first Assignment in this solution such that the list of
    /// assignments up to and including that entry satisfies term.
    func satisfier(for term: Term<Identifier>) -> Assignment<Identifier> {
        var assignedTerm: Term<Identifier>?

        for assignment in assignments {
            guard assignment.term.package == term.package else {
                continue
            }
            assignedTerm = assignedTerm.flatMap{ $0.intersect(with: assignment.term) } ?? assignment.term

            if assignedTerm!.satisfies(term) {
                return assignment
            }
        }

        fatalError("term \(term) not satisfied")
    }

    /// Backtrack to a specific decision level by dropping all assignments with
    /// a decision level which is greater.
    func backtrack(toDecisionLevel decisionLevel: Int) {
        var toBeRemoved: [(Int, Assignment<Identifier>)] = []

        for (idx, assignment) in zip(0..., assignments) {
            // Remove *all* derivations and decisions above the specified level.
            if assignment.decisionLevel > decisionLevel {
                toBeRemoved.append((idx, assignment))
            }
        }

        for (idx, remove) in toBeRemoved.reversed() {
            let assignment = assignments.remove(at: idx)
            if assignment.isDecision {
                decisions.removeValue(forKey: remove.term.package)
            }
        }

        // FIXME: We can optimize this by recomputing only the removed things.
        _negative.removeAll()
        _positive.removeAll()
        for assignment in assignments {
            register(assignment)
        }
    }

    /// Does the solution contain a decision for every derivation meaning
    /// that all necessary packages have been found?
    var isFinished: Bool {
        for derivation in assignments where !derivation.isDecision {
            if !self.decisions.keys.contains(derivation.term.package) {
                return false
            }
        }
        return true
    }

    /// Returns true if the given term satisfies the partial solution.
    func satisfies(_ term: Term<Identifier>) -> Bool {
        return self.relation(with: term) == .subset
    }

    /// Returns the set relation of the partial solution with the given term.
    func relation(with term: Term<Identifier>) -> Term<Identifier>.SetRelation {
        let pkg = term.package
        if let positive = _positive[pkg] {
            return positive.relation(with: term)
        } else if let negative = _negative[pkg] {
            return negative.relation(with: term)
        }
        return .overlap
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
        res[term.package] = (intersection!.requirement, intersection!.isPositive)
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
    private(set) var root: Identifier?

    /// The container provider used to load package containers.
    let provider: Provider

    /// The resolver's delegate.
    let delegate: Delegate?

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    /// Set the package root.
    func set(_ root: Identifier) {
        self.root = root
        self.solution.root = root
    }

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
        // FIXME: Shouldn't we check this _before_ making a decision?
        assert(term.isValidDecision(for: solution))

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
        self.set(root)
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

    public enum PubgrubError: Swift.Error, Equatable {
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
        //
        // We add the dependencies before deciding on a version for root
        // to avoid inserting the wrong decision level.
        let rootContainer = try getContainer(for: self.root!)
        for dependency in try rootContainer.getUnversionedDependencies() {
            let incompatibility = Incompatibility(
                Term(root, .versionSet(.exact("1.0.0"))),
                Term(not: dependency.identifier, dependency.requirement),
                root: root, cause: .root)
            add(incompatibility, location: .topLevel)
        }
        decide(root, version: "1.0.0", location: .topLevel)

        do {
            try run()
        } catch PubgrubError.unresolvable(let conflict) {
            let description = reportError(for: conflict)
            print(description)
            throw PubgrubError.unresolvable(conflict)
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
    func run() throws {
        var next: Identifier? = root
        while let nxt = next {
            try propagate(nxt)

            // FIXME: Is this really needed here because next should return nil
            // once version solving has finished.
            //
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
    func propagate(_ package: Identifier) throws {
        var changed: OrderedSet<Identifier> = [package]

        while !changed.isEmpty {
            let package = changed.removeFirst()

            // According to the experience of pub developers, conflict
            // resolution produces more general incompatibilities later on
            // making it advantageous to check those first.
            loop: for incompatibility in positiveIncompatibilities(for: package)?.reversed() ?? [] {
                // FIXME: This needs to find set relation for each term in the incompatibility since
                // that matters. For e.g., 1.1.0..<2.0.0 won't satisfy 1.0.0..<2.0.0 but they're
                // overlapping.
                let result = propagate(incompatibility: incompatibility)

                switch result {
                case .conflict:
                    let rootCause = try _resolve(conflict: incompatibility)
                    let rootCauseResult = propagate(incompatibility: rootCause)

                    guard case .almostSatisfied(let pkg) = rootCauseResult else {
                        fatalError("""
                            Expected root cause \(rootCause) to almost satisfy the \
                            current partial solution:
                            \(solution.assignments.map { " * \($0.description)" }.joined(separator: "\n"))\n
                            """)
                    }

                    changed.removeAll(keepingCapacity: false)
                    changed.append(pkg)
                    
                    break loop
                case .almostSatisfied(let package):
                    changed.append(package)
                case .none:
                    break
                }
            }
        }
    }

    func propagate(incompatibility: Incompatibility<Identifier>) -> PropagationResult {
        var unsatisfied: Term<Identifier>?

        for term in incompatibility.terms {
            let relation = solution.relation(with: term)

            if relation == .disjoint {
                return .none
            } else if relation == .overlap {
                if unsatisfied != nil {
                    return .none
                }
                unsatisfied = term
            }
        }

        // We have a conflict if all the terms of the incompatibility were satisfied.
        guard let unsatisfiedTerm = unsatisfied else {
            return .conflict
        }

        derive(unsatisfiedTerm.inverse, cause: incompatibility, location: .unitPropagation)

        return .almostSatisfied(package: unsatisfiedTerm.package)
    }

    enum PropagationResult {
        case conflict
        case almostSatisfied(package: Identifier)
        case none
    }

    func _resolve(conflict: Incompatibility<Identifier>) throws -> Incompatibility<Identifier> {
        // Based on:
        // https://github.com/dart-lang/pub/tree/master/doc/solver.md#conflict-resolution
        // https://github.com/dart-lang/pub/blob/master/lib/src/solver/version_solver.dart#L201
        var incompatibility = conflict
        var createdIncompatibility = false

        while !isCompleteFailure(incompatibility) {
            var mostRecentTerm: Term<Identifier>?
            var mostRecentSatisfier: Assignment<Identifier>?
            var difference: Term<Identifier>?
            var previousSatisfierLevel = 0

            for term in incompatibility.terms {
                let satisfier = solution.satisfier(for: term)

                if let _mostRecentSatisfier = mostRecentSatisfier {
                    let mostRecentSatisfierIdx = solution.assignments.index(of: _mostRecentSatisfier)!
                    let satisfierIdx = solution.assignments.index(of: satisfier)!

                    if mostRecentSatisfierIdx < satisfierIdx {
                        previousSatisfierLevel = max(previousSatisfierLevel, _mostRecentSatisfier.decisionLevel)
                        mostRecentTerm = term
                        mostRecentSatisfier = satisfier
                        difference = nil
                    } else {
                        previousSatisfierLevel = max(previousSatisfierLevel, satisfier.decisionLevel)
                    }
                } else {
                    mostRecentTerm = term
                    mostRecentSatisfier = satisfier
                }

                if mostRecentTerm == term {
                    difference = mostRecentSatisfier?.term.difference(with: term)
                    if let difference = difference {
                        previousSatisfierLevel = max(previousSatisfierLevel, solution.satisfier(for: difference.inverse).decisionLevel)
                    }
                }
            }

            guard let _mostRecentSatisfier = mostRecentSatisfier else {
                fatalError()
            }

            if previousSatisfierLevel < _mostRecentSatisfier.decisionLevel || _mostRecentSatisfier.cause == nil {
                solution.backtrack(toDecisionLevel: previousSatisfierLevel)
                if createdIncompatibility {
                    add(incompatibility, location: .conflictResolution)
                }
                return incompatibility
            }

            let priorCause = _mostRecentSatisfier.cause!

            var newTerms = incompatibility.terms.filter{ $0 != mostRecentTerm }
            newTerms += priorCause.terms.filter({ $0.package != _mostRecentSatisfier.term.package })

            if let _difference = difference {
                newTerms.append(_difference.inverse)
            }

            incompatibility = Incompatibility(
                OrderedSet(newTerms),
                root: root!,
                cause: .conflict(conflict: incompatibility, other: priorCause))
            createdIncompatibility = true
        }

        throw PubgrubError.unresolvable(incompatibility)
    }

    /// Does a given incompatibility specify that version solving has entirely
    /// failed, meaning this incompatibility is either empty or only for the root
    /// package.
    private func isCompleteFailure(_ incompatibility: Incompatibility<Identifier>) -> Bool {
        guard !incompatibility.terms.isEmpty else { return true }
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.package == root
    }

    func makeDecision() throws -> Identifier? {
        let undecided = solution.undecided

        // If there are no more undecided terms, version solving is complete.
        guard !undecided.isEmpty else {
            return nil
        }

        // FIXME: We should choose a package with least available versions for the
        // constraints that we have so far on the package.
        let pkgTerm = undecided.first!

        // Get the best available version for this package.
        guard let version = try getBestAvailableVersion(for: pkgTerm) else {
            // FIXME: It seems wrong to add the incompatibility with cause root here.
            add(Incompatibility(pkgTerm, root: root!), location: .decisionMaking)
            return pkgTerm.package
        }

        // Add all of this version's dependencies as incompatibilities.
        let depIncompatibilities = try incompatibilites(for: pkgTerm.package, at: version)

        var haveConflict = false
        for incompatibility in depIncompatibilities {
            // Add the incompatibility to our partial solution.
            add(incompatibility, location: .decisionMaking)

            // Check if this incompatibility will statisfy the solution.
            haveConflict = haveConflict || incompatibility.terms.allSatisfy {
                // We only need to check if the terms other than this package
                // are satisfied because we _know_ that the terms matching
                // this package will be satisfied if we make this version
                // as a decision.
                $0.package == pkgTerm.package || solution.satisfies($0)
            }
        }

        // Decide this version if there was no conflict with its dependencies.
        if !haveConflict {
            decide(pkgTerm.package, version: version, location: .decisionMaking)
        }

        return pkgTerm.package
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

    /// Returns the best available version for a given term.
    func getBestAvailableVersion(for term: Term<Identifier>) throws -> Version? {
        assert(term.isPositive, "Expected term to be positive")
        let container = try getContainer(for: term.package)

        switch term.requirement {
        case .versionSet(let versionSet):
            let availableVersions = container.versions(filter: { versionSet.contains($0) } )
            return availableVersions.first{ _ in true }
        case .revision:
            fatalError()
        case .unversioned:
            fatalError()
        }
    }

    /// Returns the incompatibilities of a package at the given version.
    func incompatibilites(
        for package: Identifier,
        at version: Version
    ) throws -> [Incompatibility<Identifier>] {
        let container = try getContainer(for: package)
        return try container.getDependencies(at: version).map { dep -> Incompatibility<Identifier> in
            var terms: OrderedSet<Term<Identifier>> = []

            // FIXME:
            //
            // If the selected version is the latest version, Pubgrub
            // represents the term as having an unbounded upper range.
            // We can't represent that here (currently), so we're
            // pretending that it goes to the next nonexistent major
            // version.
            let nextMajor = Version(version.major + 1, 0, 0)
            terms.append(Term(container.identifier, .versionSet(.range(version..<nextMajor))))
            terms.append(Term(not: dep.identifier, dep.requirement))
            return Incompatibility(terms, root: root!, cause: .dependency(package: container.identifier))
        }
    }
}
