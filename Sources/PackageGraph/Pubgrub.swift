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
public struct Term: Equatable, Hashable {
    let package: PackageReference
    let requirement: VersionSetSpecifier
    let isPositive: Bool

    init(package: PackageReference, requirement: VersionSetSpecifier, isPositive: Bool) {
        self.package = package
        self.requirement = requirement
        self.isPositive = isPositive
    }

    init(_ package: PackageReference, _ requirement: VersionSetSpecifier) {
        self.init(package: package, requirement: requirement, isPositive: true)
    }

    /// Create a new negative term.
    init(not package: PackageReference, _ requirement: VersionSetSpecifier) {
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
    ///
    /// - returns: `nil` if an intersection is not possible.
    func intersect(
        withRequirement requirement: VersionSetSpecifier,
        andPolarity otherIsPositive: Bool
    ) -> Term? {
        let lhs = self.requirement
        let rhs = requirement

        let intersection: VersionSetSpecifier?
        let isPositive: Bool
        switch (self.isPositive, otherIsPositive) {
        case (false, false):
            if case .range(let lhs) = lhs, case .range(let rhs) = rhs {
                let lower = min(lhs.lowerBound, rhs.lowerBound)
                let upper = max(lhs.upperBound, rhs.upperBound)
                intersection = .range(lower..<upper)
            } else {
                intersection = lhs.intersection(rhs)
            }
            isPositive = false
        case (true, true):
            intersection = lhs.intersection(rhs)
            isPositive = true
        case (true, false):
            intersection = lhs.intersection(withInverse: rhs)
            isPositive = true
        case (false, true):
            intersection = rhs.intersection(withInverse: lhs)
            isPositive = true
        }

        guard let versionIntersection = intersection, versionIntersection != .empty else {
            return nil
        }

        return Term(package: package, requirement: versionIntersection, isPositive: isPositive)
    }

    func difference(with other: Term) -> Term? {
        return self.intersect(with: other.inverse)
    }

    /// Verify if the term fulfills all requirements to be a valid choice for
    /// making a decision in the given partial solution.
    /// - There has to exist a positive derivation for it.
    /// - There has to be no decision for it.
    /// - The package version has to match all assignments.
    func isValidDecision(for solution: PartialSolution) -> Bool {
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

extension VersionSetSpecifier {
    fileprivate func containsAll(_ other: VersionSetSpecifier) -> Bool {
        return self.intersection(other) == other
    }

    fileprivate func containsAny(_ other: VersionSetSpecifier) -> Bool {
        return self.intersection(other) != .empty
    }
}

extension Term: CustomStringConvertible {
    public var description: String {
        let pkg = "\(package)"
        var req = ""

        let vs = requirement
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


        if !isPositive {
            return "¬\(pkg) \(req)"
        }
        return "\(pkg) \(req)"
    }
}

/// A set of terms that are incompatible with each other and can therefore not
/// all be true at the same time. In dependency resolution, these are derived
/// from version requirements and when running into unresolvable situations.
public struct Incompatibility: Equatable, Hashable {
    let terms: OrderedSet<Term>
    let cause: Cause

    init(terms: OrderedSet<Term>, cause: Cause) {
        self.terms = terms
        self.cause = cause
    }

    init(_ terms: Term..., root: PackageReference, cause: Cause = .root) {
        let termSet = OrderedSet(terms)
        self.init(termSet, root: root, cause: cause)
    }

    init(_ terms: OrderedSet<Term>, root: PackageReference, cause: Cause) {
        assert(terms.count > 0, "An incompatibility must contain at least one term.")

        // Remove the root package from generated incompatibilities, since it will
        // always be selected.
        var terms = terms
        if terms.count > 1,
            case .conflict(conflict: _, other: _) = cause,
            terms.contains(where: { $0.isPositive && $0.package == root }) {
            terms = OrderedSet(terms.filter { !$0.isPositive || $0.package != root })
        }

        let normalizedTerms = normalize(terms: terms.contents)
        assert(normalizedTerms.count > 0,
               "An incompatibility must contain at least one term after normalization.")
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
    indirect enum Cause: Equatable, Hashable {
        /// The root incompatibility.
        case root

        /// The incompatibility represents a package's dependency on another
        /// package.
        case dependency(package: PackageReference)

        /// The incompatibility was derived from two others during conflict
        /// resolution.
        case conflict(conflict: Incompatibility, other: Incompatibility)

        /// There exists no version to fulfill the specified requirement.
        case noAvailableVersion

        var isConflict: Bool {
            if case .conflict = self { return true }
            return false
        }

        /// Returns whether this cause can be represented in a single line of the
        /// error output.
        var isSingleLine: Bool {
            guard case .conflict(let cause) = self else {
                assertionFailure("unreachable")
                return false
            }
            return !cause.conflict.cause.isConflict && !cause.other.cause.isConflict
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
public struct Assignment: Equatable {
    let term: Term
    let decisionLevel: Int
    let cause: Incompatibility?
    let isDecision: Bool

    private init(
        term: Term,
        decisionLevel: Int,
        cause: Incompatibility?,
        isDecision: Bool
    ) {
        self.term = term
        self.decisionLevel = decisionLevel
        self.cause = cause
        self.isDecision = isDecision
    }

    /// An assignment made during decision making.
    static func decision(_ term: Term, decisionLevel: Int) -> Assignment {
        assert(term.requirement.isExact, "Cannot create a decision assignment with a non-exact version selection: \(term.requirement)")

        return self.init(
            term: term,
            decisionLevel: decisionLevel,
            cause: nil,
            isDecision: true)
    }

    /// An assignment derived from previously known incompatibilities during
    /// unit propagation.
    static func derivation(
        _ term: Term,
        cause: Incompatibility,
        decisionLevel: Int
    ) -> Assignment {
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
final class PartialSolution {
    var root: PackageReference?

    /// All known assigments.
    private(set) var assignments: [Assignment]

    /// All known decisions.
    private(set) var decisions: [PackageReference: Version] = [:]

    /// The intersection of all positive assignments for each package, minus any
    /// negative assignments that refer to that package.
    private(set) var _positive: OrderedDictionary<PackageReference, Term> = [:]

    /// Union of all negative assignments for a package.
    ///
    /// Only present if a package has no postive assignment.
    private(set) var _negative: [PackageReference: Term] = [:]

    /// The current decision level.
    var decisionLevel: Int {
        return decisions.count - 1
    }

    init(assignments: [Assignment] = []) {
        self.assignments = assignments
        for assignment in assignments {
            register(assignment)
        }
    }

    /// A list of all packages that have been assigned, but are not yet satisfied.
    var undecided: [Term] {
        return _positive.values.filter { !decisions.keys.contains($0.package) }
    }

    /// Create a new derivation assignment and add it to the partial solution's
    /// list of known assignments.
    func derive(_ term: Term, cause: Incompatibility) {
        let derivation = Assignment.derivation(term, cause: cause, decisionLevel: decisionLevel)
        self.assignments.append(derivation)
        register(derivation)
    }

    /// Create a new decision assignment and add it to the partial solution's
    /// list of known assignments.
    func decide(_ package: PackageReference, at version: Version) {
        decisions[package] = version
        let term = Term(package, .exact(version))
        let decision = Assignment.decision(term, decisionLevel: decisionLevel)
        self.assignments.append(decision)
        register(decision)
    }

    /// Populates the _positive and _negative poperties with the assignment.
    private func register(_ assignment: Assignment) {
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
    func satisfier(for term: Term) -> Assignment {
        var assignedTerm: Term?

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
        var toBeRemoved: [(Int, Assignment)] = []

        for (idx, assignment) in zip(0..., assignments) {
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

    /// Returns true if the given term satisfies the partial solution.
    func satisfies(_ term: Term) -> Bool {
        return self.relation(with: term) == .subset
    }

    /// Returns the set relation of the partial solution with the given term.
    func relation(with term: Term) -> Term.SetRelation {
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
fileprivate func normalize(
    terms: [Term]) -> [Term] {

    let dict = terms.reduce(into: OrderedDictionary<PackageReference, (req: VersionSetSpecifier, polarity: Bool)>()) {
        res, term in
        // Don't try to intersect if this is the first time we're seeing this package.
        guard let previous = res[term.package] else {
            res[term.package] = (term.requirement, term.isPositive)
            return
        }

        guard let intersection = term.intersect(withRequirement: previous.req, andPolarity: previous.polarity) else {
            fatalError("""
                Attempting to create an incompatibility with terms for \(term.package) \
                intersecting versions \(previous) and \(term.requirement). These are \
                mutually exclusive and can't be intersected, making this incompatibility \
                irrelevant.
                """)
        }
        res[term.package] = (intersection.requirement, intersection.isPositive)
    }
    return dict.map { Term(package: $0, requirement: $1.req, isPositive: $1.polarity) }
}

/// A step the resolver takes to advance its progress, e.g. deriving a new assignment
/// or creating a new incompatibility based on a package's dependencies.
public struct GeneralTraceStep: CustomStringConvertible {
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

    public var description: String {
        return "\(value) \(type) \(location) \(cause ?? "<nocause>") \(decisionLevel)"
    }
}

/// A step the resolver takes during conflict resolution.
public struct ConflictResolutionTraceStep: CustomStringConvertible {

    /// The conflicted incompatibility.
    public let incompatibility: Incompatibility

    public let term: Term

    /// The satisfying assignment.
    public let satisfier: Assignment

    public var description: String {
        return "Conflict: \(incompatibility) \(term) \(satisfier)"
    }
}

public enum TraceStep {
    case general(GeneralTraceStep)
    case conflictResolution(ConflictResolutionTraceStep)
}

public protocol Traceable: CustomStringConvertible {}
extension Incompatibility: Traceable {}
extension Term: Traceable {}

/// The solver that is able to transitively resolve a set of package constraints
/// specified by a root package.
public final class PubgrubDependencyResolver {

    /// The type of the constraints the resolver operates on.
    public typealias Constraint = PackageContainerConstraint

    /// The current best guess for a solution satisfying all requirements.
    var solution = PartialSolution()

    /// A collection of all known incompatibilities matched to the packages they
    /// refer to. This means an incompatibility can occur several times.
    var incompatibilities: [PackageReference: [Incompatibility]] = [:]

    /// Find all incompatibilities containing a positive term for a given package.
    func positiveIncompatibilities(for package: PackageReference) -> [Incompatibility]? {
        guard let all = incompatibilities[package] else {
            return nil
        }
        return all.filter {
            $0.terms.first { $0.package == package }!.isPositive
        }
    }

    /// The root package reference.
    private(set) var root: PackageReference?

    /// The container provider used to load package containers.
    let provider: PackageContainerProvider

    /// The resolver's delegate.
    let delegate: DependencyResolverDelegate?

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    /// Should resolver prefetch the containers.
    private let isPrefetchingEnabled: Bool

    /// Path to the trace file.
    fileprivate let traceFile: AbsolutePath?

    fileprivate lazy var traceStream: OutputByteStream? = {
        if let stream = self._traceStream { return stream }
        guard let traceFile = self.traceFile else { return nil }
        // FIXME: Emit a warning if this fails.
        return try? LocalFileOutputByteStream(traceFile, closeOnDeinit: true, buffered: false)
    }()
    private var _traceStream: OutputByteStream?

    /// Set the package root.
    func set(_ root: PackageReference) {
        self.root = root
        self.solution.root = root
    }

    private func log(_ assignments: [(container: PackageReference, binding: BoundVersion)]) {
        log("solved:")
        for (container, binding) in assignments {
            log("\(container) \(binding)")
        }
    }

    fileprivate func log(_ message: String) {
        if let traceStream = traceStream {
            traceStream <<< message <<< "\n"
            traceStream.flush()
        }
    }

    func trace(
        value: Traceable,
        type: GeneralTraceStep.StepType,
        location: GeneralTraceStep.Location,
        cause: String?
    ) {
        let step = GeneralTraceStep(
            value: value,
            type: type,
            location: location,
            cause: cause,
            decisionLevel: solution.decisionLevel
        )
        delegate?.trace(.general(step))
    }

    /// Trace a conflict resolution step.
    func trace(
        incompatibility: Incompatibility,
        term: Term,
        satisfier: Assignment
    ) {
        let step = ConflictResolutionTraceStep(
            incompatibility: incompatibility,
            term: term,
            satisfier: satisfier
        )
        delegate?.trace(.conflictResolution(step))
    }

    func decide(_ package: PackageReference, version: Version, location: GeneralTraceStep.Location) {
        let term = Term(package, .exact(version))
        // FIXME: Shouldn't we check this _before_ making a decision?
        assert(term.isValidDecision(for: solution))

        trace(value: term, type: .decision, location: location, cause: nil)
        solution.decide(package, at: version)
    }

    func derive(_ term: Term, cause: Incompatibility, location: GeneralTraceStep.Location) {
        trace(value: term, type: .derivation, location: location, cause: nil)
        solution.derive(term, cause: cause)
    }

    init(
        _ provider: PackageContainerProvider,
        _ delegate: DependencyResolverDelegate? = nil,
        isPrefetchingEnabled: Bool = false,
        skipUpdate: Bool = false,
        traceFile: AbsolutePath? = nil,
        traceStream: OutputByteStream? = nil
    ) {
        self.provider = provider
        self.delegate = delegate
        self.isPrefetchingEnabled = isPrefetchingEnabled
        self.skipUpdate = skipUpdate
        self.traceFile = traceFile
        self._traceStream = traceStream
    }

    public convenience init(
        _ provider: PackageContainerProvider,
        _ delegate: DependencyResolverDelegate? = nil,
        isPrefetchingEnabled: Bool = false,
        skipUpdate: Bool = false,
        traceFile: AbsolutePath? = nil
    ) {
        self.init(provider, delegate, isPrefetchingEnabled: isPrefetchingEnabled, skipUpdate: skipUpdate, traceFile: traceFile, traceStream: nil)
    }

    /// Add a new incompatibility to the list of known incompatibilities.
    func add(_ incompatibility: Incompatibility, location: GeneralTraceStep.Location) {
        log("incompat: \(incompatibility) \(location)")
        trace(value: incompatibility, type: .incompatibility, location: location, cause: nil)
        for package in incompatibility.terms.map({ $0.package }) {
            if let incompats = incompatibilities[package] {
                if !incompats.contains(incompatibility) {
                    incompatibilities[package]!.append(incompatibility)
                }
            } else {
                incompatibilities[package] = [incompatibility]
            }
        }
    }

    public typealias Result = DependencyResolver.Result

    public enum PubgrubError: Swift.Error, Equatable, CustomStringConvertible {
        case _unresolvable(Incompatibility)
        case unresolvable(String)

        public var description: String {
            switch self {
            case ._unresolvable(let rootCause):
                return rootCause.description
            case .unresolvable(let error):
                return error
            }
        }

        var rootCause: Incompatibility? {
            switch self {
            case ._unresolvable(let rootCause):
                return rootCause
            case .unresolvable:
                return nil
            }
        }
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    public func solve(dependencies: [Constraint], pins: [Constraint] = []) -> Result {
        do {
            return try .success(solve(constraints: dependencies, pins: pins))
        } catch {
            var error = error

            // If version solving failing, build the user-facing diagnostic.
            if let pubGrubError = error as? PubgrubError, let rootCause = pubGrubError.rootCause {
                let diagnostic = diagnosticBuilder.reportError(for: rootCause)
                error = PubgrubError.unresolvable(diagnostic)
            }

            return .error(error)
        }
    }

    struct VersionBasedConstraint {
        let package: PackageReference
        let requirement: VersionSetSpecifier

        init(package: PackageReference, req: VersionSetSpecifier) {
            self.package = package
            self.requirement = req
        }

        init?(_ constaint: Constraint) {
            switch constaint.requirement {
            case .versionSet(let req):
                self.package = constaint.identifier
                self.requirement = req
            case .revision:
                return nil
            case .unversioned:
                return nil
            }
        }
    }

    private func processInputs(
        with constraints: [Constraint]
    ) throws -> (overriddenPackages: [PackageReference: BoundVersion], rootIncompatibilities: [Incompatibility]) {
        let root = self.root!

        // The list of constraints that we'll be working with. We start with the input constraints
        // and process them in two phases. The first phase finds all unversioned constraints and
        // the second phase discovers all branch-based constraints.
        var constraints = OrderedSet(constraints)

        // The list of packages that are overridden in the graph. A local package reference will
        // always override any other kind of package reference and branch-based reference will override
        // version-based reference.
        var overridenPackages: [PackageReference: BoundVersion] = [:]

        // The list of version-based references reachable via local and branch-based references.
        // These are added as top-level incompatibilities since they always need to be statisfied.
        // Some of these might be overridden as we discover local and branch-based references.
        var versionBasedDependencies: [PackageReference: [VersionBasedConstraint]] = [:]

        // Process unversioned constraints in first phase. We go through all of the unversioned packages
        // and collect them and their dependencies. This gives us the complete list of unversioned
        // packages in the graph since unversioned packages can only be refered by other
        // unversioned packages.
        while let constraint = constraints.first(where: { $0.requirement == .unversioned }) {
            constraints.remove(constraint)

            // Mark the package as overridden.
            let package = constraint.identifier
            overridenPackages[package] = .unversioned

            // Process dependencies of this package.
            //
            // We collect all version-based dependencies in a separate structure so they can
            // be process at the end. This allows us to override them when there is a non-version
            // based (unversioned/branch-based) constraint present in the graph.
            let container = try getContainer(for: package)
            for dependency in try container.getUnversionedDependencies() {
                if let versionedBasedConstraint = VersionBasedConstraint(dependency) {
                    versionBasedDependencies[package, default: []].append(versionedBasedConstraint)
                } else {
                    constraints.append(dependency)
                }
            }
        }

        // Process revision-based constraints in the second phase. Here we do the similar processing
        // as the first phase but we also ignore the constraints that are overriden due to
        // presence of unversioned constraints.
        while let constraint = constraints.first(where: { $0.requirement.isRevision }) {
            guard case .revision(let revision) = constraint.requirement else { fatalError("Expected revision requirement") }
            constraints.remove(constraint)
            let package = constraint.identifier

            // Check if there is an existing value for this package in the overridden packages.
            switch overridenPackages[package] {
                case .excluded?, .version?:
                    // These values are not possible.
                    fatalError("Unexpected value for overriden package \(package) in \(overridenPackages)")
                case .unversioned?:
                    // This package is overridden by an unversioned package so we can ignore this constraint.
                    continue
                case .revision(let existingRevision)?:
                    // If this branch-based package was encountered before, ensure the references match.
                    if existingRevision != revision {
                        // FIXME: Improve diagnostics here.
                        throw PubgrubError.unresolvable("Revision mismatch for \(package): \(existingRevision) \(revision)")
                    }
                case nil:
                    break
            }

            // Mark the package as overridden.
            overridenPackages[package] = .revision(revision)

            // Process dependencies of this package, similar to the first phase but branch-based dependencies
            // are not allowed to contain local/unversioned packages.
            let container = try getContainer(for: package)
            for dependency in try container.getDependencies(at: revision) {
                switch dependency.requirement {
                case .versionSet(let req):
                    let versionedBasedConstraint = VersionBasedConstraint(package: dependency.identifier, req: req)
                    versionBasedDependencies[package, default: []].append(versionedBasedConstraint)
                case .revision:
                    constraints.append(dependency)
                case .unversioned:
                    throw DependencyResolverError.revisionDependencyContainsLocalPackage(
                        dependency: package.identity,
                        localPackage: dependency.identifier.identity
                    )
                }
            }
        }

        // At this point, we should be left with only version-based requirements in our constraints
        // list. Add them to our version-based dependency list.
        for dependency in constraints {
            switch dependency.requirement {
            case .versionSet(let req):
                let versionedBasedConstraint = VersionBasedConstraint(package: dependency.identifier, req: req)
                // FIXME: It would be better to record where this constraint came from, instead of just
                // using root.
                versionBasedDependencies[root, default: []].append(versionedBasedConstraint)
            case .revision, .unversioned:
                fatalError("Unexpected revision/unversioned requirement in the constraints list: \(constraints)")
            }
        }

        // Finally, compute the root incompatibilities (which will be all version-based).
        var rootIncompatibilities: [Incompatibility] = []
        for (package, constraints) in versionBasedDependencies {
            for constraint in constraints {
                if overridenPackages.keys.contains(constraint.package) { continue }

                let incompat = Incompatibility(
                    Term(root, .exact("1.0.0")),
                    Term(not: constraint.package, constraint.requirement),
                    root: root,
                    cause: .dependency(package: package))
                rootIncompatibilities.append(incompat)
            }
        }

        return (overridenPackages, rootIncompatibilities)
    }

    /// The list of packages that are overridden in the graph. A local package reference will
    /// always override any other kind of package reference and branch-based reference will override
    /// version-based reference.
    private var overriddenPackages: [PackageReference: BoundVersion] = [:]

    /// Find a set of dependencies that fit the given constraints. If dependency
    /// resolution is unable to provide a result, an error is thrown.
    /// - Warning: It is expected that the root package reference has been set
    ///            before this is called.
    private func solve(
        constraints: [Constraint], pins: [Constraint] = []
    ) throws -> [(container: PackageReference, binding: BoundVersion)] {
        let root = PackageReference(
            identity: "<synthesized-root>",
            path: "<synthesized-root-path>",
            name: nil,
            isLocal: true
        )

        self.root = root

        // Add the root incompatibility.
        let rootIncompatibility = Incompatibility(
            terms: [Term(not: root, .exact("1.0.0"))],
            cause: .root
        )
        add(rootIncompatibility, location: .topLevel)

        let inputs = try processInputs(with: pins + constraints)
        self.overriddenPackages = inputs.overriddenPackages

        // Add all the root incompatibilities.
        for incompat in inputs.rootIncompatibilities {
            add(incompat, location: .topLevel)
        }

        // Decide root at v1.
        decide(root, version: "1.0.0", location: .topLevel)

        try run()

        let decisions = solution.assignments.filter { $0.isDecision }
        var finalAssignments: [(container: PackageReference, binding: BoundVersion)] = try decisions.compactMap { assignment in
            guard assignment.term.package != root else {
                return nil
            }

            var boundVersion: BoundVersion
            switch assignment.term.requirement {
            case .exact(let version):
                boundVersion = .version(version)
            case .range, .any, .empty:
                fatalError("unexpected requirement value for assignment \(assignment.term)")
            }

            let container = try getContainer(for: assignment.term.package)
            let identifier = try container.getUpdatedIdentifier(at: boundVersion)

            return (identifier, boundVersion)
        }

        // Add overriden packages to the result.
        for (package, boundVersion) in overriddenPackages {
            let container = try getContainer(for: package)
            let identifier = try container.getUpdatedIdentifier(at: boundVersion)
            finalAssignments.append((identifier, boundVersion))
        }

        log(finalAssignments)

        return finalAssignments
    }

    /// Perform unit propagation, resolving conflicts if necessary and making
    /// decisions if nothing else is left to be done.
    /// After this method returns `solution` is either populated with a list of
    /// final version assignments or an error is thrown.
    func run() throws {
        var next: PackageReference? = root
        while let nxt = next {
            try propagate(nxt)

            // If decision making determines that no more decisions are to be
            // made, it returns nil to signal that version solving is done.
            next = try makeDecision()
        }
    }

    /// Perform unit propagation to derive new assignments based on the current
    /// partial solution.
    /// If a conflict is found, the conflicting incompatibility is returned to
    /// resolve the conflict on.
    func propagate(_ package: PackageReference) throws {
        var changed: OrderedSet<PackageReference> = [package]

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

    func propagate(incompatibility: Incompatibility) -> PropagationResult {
        var unsatisfied: Term?

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

        log("derived: \(unsatisfiedTerm.inverse)")
        derive(unsatisfiedTerm.inverse, cause: incompatibility, location: .unitPropagation)

        return .almostSatisfied(package: unsatisfiedTerm.package)
    }

    enum PropagationResult {
        case conflict
        case almostSatisfied(package: PackageReference)
        case none
    }

    func _resolve(conflict: Incompatibility) throws -> Incompatibility {
        log("conflict: \(conflict)");
        // Based on:
        // https://github.com/dart-lang/pub/tree/master/doc/solver.md#conflict-resolution
        // https://github.com/dart-lang/pub/blob/master/lib/src/solver/version_solver.dart#L201
        var incompatibility = conflict
        var createdIncompatibility = false

        while !isCompleteFailure(incompatibility) {
            var mostRecentTerm: Term?
            var mostRecentSatisfier: Assignment?
            var difference: Term?
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

            log("CR: \(mostRecentTerm?.description ?? "") is\(difference != nil ? " partially" : "") satisfied by \(_mostRecentSatisfier)")
            log("CR: which is caused by \(_mostRecentSatisfier.cause?.description ?? "")")
            log("CR: new incompatibility \(incompatibility)")
        }

        log("failed: \(incompatibility)")
        throw PubgrubError._unresolvable(incompatibility)
    }

    /// Does a given incompatibility specify that version solving has entirely
    /// failed, meaning this incompatibility is either empty or only for the root
    /// package.
    private func isCompleteFailure(_ incompatibility: Incompatibility) -> Bool {
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.package == root
    }

    func makeDecision() throws -> PackageReference? {
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
            add(Incompatibility(pkgTerm, root: root!, cause: .noAvailableVersion), location: .decisionMaking)
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
            log("decision: \(pkgTerm.package)@\(version)")
            decide(pkgTerm.package, version: version, location: .decisionMaking)
        }

        return pkgTerm.package
    }

    // MARK: - Error Reporting

    // FIXME: Convert this into a method.
    var diagnosticBuilder: DiagnosticReportBuilder {
        return DiagnosticReportBuilder(
            root: root!,
            incompatibilities: incompatibilities
        )
    }

    // MARK: - Container Management

    /// Condition for container management structures.
    private let fetchCondition = Condition()

    /// The list of fetched containers.
    private var _fetchedContainers: [PackageReference: Basic.Result<PackageContainer, AnyError>] = [:]

    /// The set of containers requested so far.
    private var _prefetchingContainers: Set<PackageReference> = []

    /// Get the container for the given identifier, loading it if necessary.
    fileprivate func getContainer(for identifier: PackageReference) throws -> PackageContainer {
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
    func getBestAvailableVersion(for term: Term) throws -> Version? {
        assert(term.isPositive, "Expected term to be positive")
        let container = try getContainer(for: term.package)

        let versionSet = term.requirement
        let availableVersions = container.versions(filter: { versionSet.contains($0) } )
        return availableVersions.first { _ in true }
    }

    /// Returns the incompatibilities of a package at the given version.
    func incompatibilites(
        for package: PackageReference,
        at version: Version
    ) throws -> [Incompatibility] {
        let container = try getContainer(for: package)
        return try container.getDependencies(at: version).compactMap { dep -> Incompatibility? in
            guard case .versionSet(let vs) = dep.requirement else {
                fatalError("Expected \(dep) to be pinned to a version set, not \(dep.requirement).")
            }

            if overriddenPackages.keys.contains(dep.identifier) {
                return nil
            }

            var terms: OrderedSet<Term> = []
            // FIXME:
            //
            // If the selected version is the latest version, Pubgrub
            // represents the term as having an unbounded upper range.
            // We can't represent that here (currently), so we're
            // pretending that it goes to the next nonexistent major
            // version.
            //
            // FIXME: This is completely wrong when a dependencies change
            // across version. It leads to us not being able to diagnose
            // resolution errors properly. We only end up showing the
            // the problem with the oldest version.
            let nextMajor = Version(version.major + 1, 0, 0)
            terms.append(Term(container.identifier, .range(version..<nextMajor)))
            terms.append(Term(not: dep.identifier, vs))
            return Incompatibility(terms, root: root!, cause: .dependency(package: container.identifier))
        }
    }

    /// Starts prefetching the given containers.
    private func prefetch(containers identifiers: [PackageReference]) {
        fetchCondition.whileLocked {
            // Process each container.
            for identifier in identifiers {
                // Skip if we're already have this container or are pre-fetching it.
                guard _fetchedContainers[identifier] == nil,
                    !_prefetchingContainers.contains(identifier) else {
                        continue
                }

                // Otherwise, record that we're prefetching this container.
                _prefetchingContainers.insert(identifier)

                provider.getContainer(for: identifier, skipUpdate: skipUpdate) { container in
                    self.fetchCondition.whileLocked {
                        // Update the structures and signal any thread waiting
                        // on prefetching to finish.
                        self._fetchedContainers[identifier] = container
                        self._prefetchingContainers.remove(identifier)
                        self.fetchCondition.signal()
                    }
                }
            }
        }
    }
}

final class DiagnosticReportBuilder {
    let rootPackage: PackageReference
    let incompatibilities: [PackageReference: [Incompatibility]]

    private var lines: [(String, Int)] = []
    private var derivations: [Incompatibility: Int] = [:]
    private var lineNumbers: [Incompatibility: Int] = [:]

    init(root: PackageReference, incompatibilities: [PackageReference: [Incompatibility]]) {
        self.rootPackage = root
        self.incompatibilities = incompatibilities
    }

    func reportError(for incompatibility: Incompatibility) -> String {
        /// Populate `derivations`.
        func countDerivations(_ i: Incompatibility) {
            derivations[i, default: 0] += 1
            if case .conflict(let lhs, let rhs) = i.cause {
                countDerivations(lhs)
                countDerivations(rhs)
            }
        }

        countDerivations(incompatibility)

        if incompatibility.cause.isConflict {
            visit(incompatibility)
        } else {
            assertionFailure("Unimplemented")
            write(
                incompatibility,
                message: "Because \(description(for: incompatibility)), version solving failed.",
                isNumbered: false)
        }


        let stream = BufferedOutputByteStream()
        let padding = lineNumbers.isEmpty ? 0 : "\(lineNumbers.values.map{$0}.last!) ".count

        for (idx, line) in lines.enumerated() {
            let message = line.0
            let number = line.1
            stream <<< Format.asRepeating(string: " ", count: padding)
            if (number != -1) {
                stream <<< Format.asRepeating(string: " ", count: padding)
                stream <<< " (\(number)) "
            }
            stream <<< message

            if lines.count - 1 != idx {
                stream <<< "\n"
            }
        }

        return stream.bytes.description
    }

    private func visit(
        _ incompatibility: Incompatibility,
        isConclusion: Bool = false
    ) {
        let isNumbered = isConclusion || derivations[incompatibility]! > 1
        let conjunction = isConclusion || incompatibility.cause == .root ? "So," : "And"
        let incompatibilityDesc = description(for: incompatibility)

        guard case .conflict(let cause) = incompatibility.cause else {
            assertionFailure("\(incompatibility)")
            return
        }

        if cause.conflict.cause.isConflict && cause.other.cause.isConflict {
            let conflictLine = lineNumbers[cause.conflict]
            let otherLine = lineNumbers[cause.other]

            if let conflictLine = conflictLine, let otherLine = otherLine {
                write(
                    incompatibility,
                    message: "Because \(description(for: cause.conflict)) (\(conflictLine)) and \(description(for: cause.other)) (\(otherLine), \(incompatibilityDesc).",
                    isNumbered: isNumbered)
            } else if conflictLine != nil || otherLine != nil {
                let withLine: Incompatibility
                let withoutLine: Incompatibility
                let line: Int
                if let conflictLine = conflictLine {
                    withLine = cause.conflict
                    withoutLine = cause.other
                    line = conflictLine
                } else {
                    withLine = cause.other
                    withoutLine = cause.conflict
                    line = otherLine!
                }

                visit(withoutLine)
                write(
                    incompatibility,
                    message: "\(conjunction) because \(description(for: withLine)) \(line), \(incompatibilityDesc).",
                    isNumbered: isNumbered)
            } else {
                let singleLineConflict = cause.conflict.cause.isSingleLine
                let singleLineOther = cause.other.cause.isSingleLine
                if singleLineOther || singleLineConflict {
                    let first = singleLineOther ? cause.conflict : cause.other
                    let second = singleLineOther ? cause.other : cause.conflict
                    visit(first)
                    visit(second)
                    write(
                        incompatibility,
                        message: "Thus, \(incompatibilityDesc).",
                        isNumbered: isNumbered)
                } else {
                    visit(cause.conflict, isConclusion: true)
                    visit(cause.other)
                    write(
                        incompatibility,
                        message: "\(conjunction) because \(description(for: cause.conflict)) (\(lineNumbers[cause.conflict]!)), \(incompatibilityDesc).",
                        isNumbered: isNumbered)
                }
            }
        } else if cause.conflict.cause.isConflict || cause.other.cause.isConflict {
            let derived =
                cause.conflict.cause.isConflict ? cause.conflict : cause.other
            let ext =
                cause.conflict.cause.isConflict ? cause.other : cause.conflict
            let derivedLine = lineNumbers[derived]
            if let derivedLine = derivedLine {
                write(
                    incompatibility,
                    message: "because \(description(for: ext)) and \(description(for: derived)) (\(derivedLine)), \(incompatibilityDesc).",
                    isNumbered: isNumbered)
            } else if isCollapsible(derived) {
                guard case .conflict(let derivedCause) = derived.cause else {
                    assertionFailure("unreachable")
                    return
                }

                let collapsedDerived = derivedCause.conflict.cause.isConflict ? derivedCause.conflict : derivedCause.other
                let collapsedExt = derivedCause.conflict.cause.isConflict ? derivedCause.other : derivedCause.conflict

                visit(collapsedDerived)
                write(
                    incompatibility,
                    message: "\(conjunction) because \(description(for: collapsedExt)) and \(description(for: ext)), \(incompatibilityDesc).",
                    isNumbered: isNumbered)
            } else {
                visit(derived)
                write(
                    incompatibility,
                    message: "\(conjunction) because \(description(for: ext)), \(incompatibilityDesc).",
                    isNumbered: isNumbered)
            }
        } else {
            write(
                incompatibility,
                message: "because \(description(for: cause.conflict)) and \(description(for: cause.other)), \(incompatibilityDesc).",
                isNumbered: isNumbered)
        }
    }

    private func description(for incompatibility: Incompatibility) -> String {
        switch incompatibility.cause {
        case .dependency(package: _):
            assert(incompatibility.terms.count == 2)
            let depender = incompatibility.terms.first!
            let dependee = incompatibility.terms.last!
            assert(depender.isPositive)
            assert(!dependee.isPositive)

            let dependerDesc = description(for: depender)
            let dependeeDesc = description(for: dependee)
            return "\(dependerDesc) depends on \(dependeeDesc)"
        case .noAvailableVersion:
            assert(incompatibility.terms.count == 1)
            let package = incompatibility.terms.first!
            assert(package.isPositive)
            return "no versions of \(package.package.identity) match the requirement \(package.requirement)"
        case .root:
            // FIXME: This will never happen I think.
            assert(incompatibility.terms.count == 1)
            let package = incompatibility.terms.first!
            assert(package.isPositive)
            return "\(package.package.identity) is \(package.requirement)"
        default: break
        }

        if isFailure(incompatibility) {
            return "version solving failed"
        }

        // FIXME: Need to show requirements for some of these.

        let terms = incompatibility.terms
        if terms.count == 1 {
            let term = terms.first!
            return "\(term) is " + (term.isPositive ? "forbidden" : "required")
        } else if terms.count == 2 {
            let term1 = terms.first!
            let term2 = terms.last!
            if term1.isPositive == term2.isPositive {
                if term1.isPositive {
                    return "\(term1.package.identity) is incompatible with \(term2.package.identity)";
                } else {
                    return "either \(term1.package.identity) or \(term2)"
                }
            }
        }

        let positive = terms.filter{ $0.isPositive }.map{ $0.package.identity }
        let negative = terms.filter{ !$0.isPositive }.map{ $0.package.identity }
        if !positive.isEmpty && !negative.isEmpty {
            if positive.count == 1 {
                return "\(positive[0]) requires \(negative.joined(separator: " or "))";
            } else {
                return "if \(positive.joined(separator: " and ")) then \(negative.joined(separator: " or "))";
            }
        } else if !positive.isEmpty {
            return "one of \(positive.joined(separator: " or ")) must be true"
        } else {
            return "one of \(negative.joined(separator: " or ")) must be true"
        }
    }

    private func isCollapsible(_ incompatibility: Incompatibility) -> Bool {
        if derivations[incompatibility]! > 1 {
            return false
        }

        guard case .conflict(let cause) = incompatibility.cause else {
            assertionFailure("unreachable")
            return false
        }

        if cause.conflict.cause.isConflict && cause.other.cause.isConflict {
            return false
        }

        if !cause.conflict.cause.isConflict && !cause.other.cause.isConflict {
            return false
        }

        let complex = cause.conflict.cause.isConflict ? cause.conflict : cause.other
        return !lineNumbers.keys.contains(complex)
    }

    // FIXME: This is duplicated and wrong.
    private func isFailure(_ incompatibility: Incompatibility) -> Bool {
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.package.identity == "<synthesized-root>"
    }

    private func description(for term: Term) -> String {
        let name = term.package.name ?? term.package.identity

            switch term.requirement {
            case .any: return "any version of \(name)"
            case .empty: return "no version of \(name)"
            case .exact(let version):
                // For the root package, don't output the useless version 1.0.0.
                if term.package == rootPackage {
                    return "root"
                }
                return "\(name) @\(version)"
            case .range(let range):
                let upper = range.upperBound
                let nextMajor = Version(range.lowerBound.major + 1, 0, 0)
                if upper == nextMajor {
                    return "\(name) ^\(range.lowerBound)"
                } else {
                    return "\(name) \(range.description)"
                }
            }
        }

    /// Write a given output message to a stream. The message should describe
    /// the incompatibility and how it as derived. If `isNumbered` is true, a
    /// line number will be assigned to this incompatibility so that it can be
    /// referred to again.
    private func write(
        _ i: Incompatibility,
        message: String,
        isNumbered: Bool
    ) {
        var number = -1
        if isNumbered {
            number = lineNumbers.count + 1
            lineNumbers[i] = number
        }
        lines.append((message, number))
    }
}

extension BoundVersion {
    fileprivate func toRequirement() -> VersionSetSpecifier {
        switch self {
        case .version(let version):
            return .exact(version)
        case .excluded, .unversioned, .revision:
            fatalError("Cannot create package requirement from excluded version.")
        }
    }
}

extension VersionSetSpecifier {
    fileprivate var isExact: Bool {
        switch self {
        case .any, .empty, .range:
            return false
        case .exact:
            return true
        }
    }
}

extension PackageRequirement {
    fileprivate var isVersionSet: Bool {
        switch self {
        case .versionSet:
            return true
        case .revision, .unversioned:
            return false
        }
    }

    fileprivate var isRevision: Bool {
        switch self {
        case .versionSet, .unversioned:
            return false
        case .revision:
            return true
        }
    }
}
