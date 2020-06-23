/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct TSCUtility.Version
import TSCBasic
import PackageModel
import Dispatch

/// A term represents a statement about a package that may be true or false.
public struct Term: Equatable, Hashable {
    public let node: DependencyResolutionNode
    public let requirement: VersionSetSpecifier
    public let isPositive: Bool

    public init(node: DependencyResolutionNode, requirement: VersionSetSpecifier, isPositive: Bool) {
        self.node = node
        self.requirement = requirement
        self.isPositive = isPositive
    }

    public init(_ node: DependencyResolutionNode, _ requirement: VersionSetSpecifier) {
        self.init(node: node, requirement: requirement, isPositive: true)
    }

    /// Create a new negative term.
    public init(not node: DependencyResolutionNode, _ requirement: VersionSetSpecifier) {
        self.init(node: node, requirement: requirement, isPositive: false)
    }

    /// The same term with an inversed `isPositive` value.
    public var inverse: Term {
        return Term(
            node: node,
            requirement: requirement,
            isPositive: !isPositive)
    }

    /// Check if this term satisfies another term, e.g. if `self` is true,
    /// `other` must also be true.
    public func satisfies(_ other: Term) -> Bool {
        // TODO: This probably makes more sense as isSatisfied(by:) instead.
        guard self.node == other.node else { return false }
        return self.relation(with: other) == .subset
    }

    /// Create an intersection with another term.
    public func intersect(with other: Term) -> Term? {
        guard self.node == other.node else { return nil }
        return intersect(withRequirement: other.requirement, andPolarity: other.isPositive)
    }

    /// Create an intersection with a requirement and polarity returning a new
    /// term which represents the version constraints allowed by both the current
    /// and given term.
    ///
    /// - returns: `nil` if an intersection is not possible.
    public func intersect(
        withRequirement requirement: VersionSetSpecifier,
        andPolarity otherIsPositive: Bool
    ) -> Term? {
        let lhs = self.requirement
        let rhs = requirement

        let intersection: VersionSetSpecifier?
        let isPositive: Bool
        switch (self.isPositive, otherIsPositive) {
        case (false, false):
            intersection = lhs.union(rhs)
            isPositive = false
        case (true, true):
            intersection = lhs.intersection(rhs)
            isPositive = true
        case (true, false):
            intersection = lhs.difference(rhs)
            isPositive = true
        case (false, true):
            intersection = rhs.difference(lhs)
            isPositive = true
        }

        guard let versionIntersection = intersection, versionIntersection != .empty else {
            return nil
        }

        return Term(node: node, requirement: versionIntersection, isPositive: isPositive)
    }

    public func difference(with other: Term) -> Term? {
        return self.intersect(with: other.inverse)
    }

    /// Verify if the term fulfills all requirements to be a valid choice for
    /// making a decision in the given partial solution.
    /// - There has to exist a positive derivation for it.
    /// - There has to be no decision for it.
    /// - The package version has to match all assignments.
    public func isValidDecision(for solution: PartialSolution) -> Bool {
        for assignment in solution.assignments where assignment.term.node == node {
            assert(!assignment.isDecision, "Expected assignment to be a derivation.")
            guard satisfies(assignment.term) else { return false }
        }
        return true
    }

    public func relation(with other: Term) -> SetRelation {
        // From: https://github.com/dart-lang/pub/blob/master/lib/src/solver/term.dart

        if self.node != other.node {
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

    public enum SetRelation: Equatable {
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
        let pkg = "\(node)"
        let req = requirement.description

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
    public let terms: OrderedSet<Term>
    public let cause: Cause

    public init(terms: OrderedSet<Term>, cause: Cause) {
        self.terms = terms
        self.cause = cause
    }

    public init(_ terms: Term..., root: DependencyResolutionNode, cause: Cause = .root) {
        let termSet = OrderedSet(terms)
        self.init(termSet, root: root, cause: cause)
    }

    public init(_ terms: OrderedSet<Term>, root: DependencyResolutionNode, cause: Cause) {
        if terms.isEmpty {
            self.init(terms: terms, cause: cause)
            return
        }

        // Remove the root package from generated incompatibilities, since it will
        // always be selected.
        var terms = terms
        if terms.count > 1, cause.isConflict,
            terms.contains(where: { $0.isPositive && $0.node == root }) {
            terms = OrderedSet(terms.filter { !$0.isPositive || $0.node != root })
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
    public indirect enum Cause: Equatable, Hashable {
        public struct ConflictCause: Hashable {
            public let conflict: Incompatibility
            public let other: Incompatibility
        }

        /// The root incompatibility.
        case root

        /// The incompatibility represents a package's dependency on another
        /// package.
        case dependency(node: DependencyResolutionNode)

        /// The incompatibility was derived from two others during conflict
        /// resolution.
        case conflict(cause: ConflictCause)

        /// There exists no version to fulfill the specified requirement.
        case noAvailableVersion

        /// A version-based dependency contains unversioned-based dependency.
        case versionBasedDependencyContainsUnversionedDependency(versionedDependency: String, unversionedDependency: String)

        /// The package's tools version is incompatible.
        case incompatibleToolsVersion

        public var isConflict: Bool {
            if case .conflict = self { return true }
            return false
        }

        /// Returns whether this cause can be represented in a single line of the
        /// error output.
        public var isSingleLine: Bool {
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
    public let term: Term
    public let decisionLevel: Int
    public let cause: Incompatibility?
    public let isDecision: Bool

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
    public static func decision(_ term: Term, decisionLevel: Int) -> Assignment {
        assert(term.requirement.isExact, "Cannot create a decision assignment with a non-exact version selection: \(term.requirement)")

        return self.init(
            term: term,
            decisionLevel: decisionLevel,
            cause: nil,
            isDecision: true)
    }

    /// An assignment derived from previously known incompatibilities during
    /// unit propagation.
    public static func derivation(
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
public final class PartialSolution {
    var root: DependencyResolutionNode?

    /// All known assigments.
    public private(set) var assignments: [Assignment]

    /// All known decisions.
    public private(set) var decisions: [DependencyResolutionNode: Version] = [:]

    /// The intersection of all positive assignments for each package, minus any
    /// negative assignments that refer to that package.
    public private(set) var _positive: OrderedDictionary<DependencyResolutionNode, Term> = [:]

    /// Union of all negative assignments for a package.
    ///
    /// Only present if a package has no postive assignment.
    public private(set) var _negative: [DependencyResolutionNode: Term] = [:]

    /// The current decision level.
    public var decisionLevel: Int {
        return decisions.count - 1
    }

    public init(assignments: [Assignment] = []) {
        self.assignments = assignments
        for assignment in assignments {
            register(assignment)
        }
    }

    /// A list of all packages that have been assigned, but are not yet satisfied.
    public var undecided: [Term] {
        return _positive.values.filter { !decisions.keys.contains($0.node) }
    }

    /// Create a new derivation assignment and add it to the partial solution's
    /// list of known assignments.
    public func derive(_ term: Term, cause: Incompatibility) {
        let derivation = Assignment.derivation(term, cause: cause, decisionLevel: decisionLevel)
        self.assignments.append(derivation)
        register(derivation)
    }

    /// Create a new decision assignment and add it to the partial solution's
    /// list of known assignments.
    public func decide(_ node: DependencyResolutionNode, at version: Version) {
        decisions[node] = version
        let term = Term(node, .exact(version))
        let decision = Assignment.decision(term, decisionLevel: decisionLevel)
        self.assignments.append(decision)
        register(decision)
    }

    /// Populates the _positive and _negative poperties with the assignment.
    private func register(_ assignment: Assignment) {
        let term = assignment.term
        let pkg = term.node

        if let positive = _positive[pkg] {
            _positive[term.node] = positive.intersect(with: term)
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
    public func satisfier(for term: Term) -> Assignment {
        var assignedTerm: Term?

        for assignment in assignments {
            guard assignment.term.node == term.node else {
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
    public func backtrack(toDecisionLevel decisionLevel: Int) {
        var toBeRemoved: [(Int, Assignment)] = []

        for (idx, assignment) in zip(0..., assignments) {
            if assignment.decisionLevel > decisionLevel {
                toBeRemoved.append((idx, assignment))
            }
        }

        for (idx, remove) in toBeRemoved.reversed() {
            let assignment = assignments.remove(at: idx)
            if assignment.isDecision {
                decisions.removeValue(forKey: remove.term.node)
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
        let pkg = term.node
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

    let dict = terms.reduce(into: OrderedDictionary<DependencyResolutionNode, (req: VersionSetSpecifier, polarity: Bool)>()) {
        res, term in
        // Don't try to intersect if this is the first time we're seeing this package.
        guard let previous = res[term.node] else {
            res[term.node] = (term.requirement, term.isPositive)
            return
        }

        guard let intersection = term.intersect(withRequirement: previous.req, andPolarity: previous.polarity) else {
            fatalError("""
                Attempting to create an incompatibility with terms for \(term.node) \
                intersecting versions \(previous) and \(term.requirement). These are \
                mutually exclusive and can't be intersected, making this incompatibility \
                irrelevant.
                """)
        }
        res[term.node] = (intersection.requirement, intersection.isPositive)
    }
    return dict.map { Term(node: $0, requirement: $1.req, isPositive: $1.polarity) }
}

/// The solver that is able to transitively resolve a set of package constraints
/// specified by a root package.
public final class PubgrubDependencyResolver {

    /// The type of the constraints the resolver operates on.
    public typealias Constraint = PackageContainerConstraint

    /// The current best guess for a solution satisfying all requirements.
    public var solution = PartialSolution()

    /// A collection of all known incompatibilities matched to the packages they
    /// refer to. This means an incompatibility can occur several times.
    public var incompatibilities: [DependencyResolutionNode: [Incompatibility]] = [:]

    /// Find all incompatibilities containing a positive term for a given package.
    public func positiveIncompatibilities(for node: DependencyResolutionNode) -> [Incompatibility]? {
        guard let all = incompatibilities[node] else {
            return nil
        }
        return all.filter {
            $0.terms.first { $0.node == node }!.isPositive
        }
    }

    /// The root package reference.
    private(set) var root: DependencyResolutionNode?

    /// Reference to the pins store, if provided.
    private var pinsMap: PinsStore.PinsMap = [:]

    /// The container provider used to load package containers.
    private lazy var provider: ContainerProvider = {
        ContainerProvider(self.packageContainerProvider, skipUpdate: self.skipUpdate, pinsMap: self.pinsMap)
    }()

    /// The resolver's delegate.
    let delegate: DependencyResolverDelegate?

    /// Skip updating containers while fetching them.
    private let skipUpdate: Bool

    /// Reference to the package container provider.
    private let packageContainerProvider: PackageContainerProvider

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
    public func set(_ root: DependencyResolutionNode) {
        self.root = root
        self.solution.root = root
    }

    public enum LogLocation: String {
        case topLevel = "top level"
        case unitPropagation = "unit propagation"
        case decisionMaking = "decision making"
        case conflictResolution = "conflict resolution"
    }

    private func log(_ assignments: [(container: PackageReference, binding: BoundVersion, products: ProductFilter)]) {
        log("solved:")
        for (container, binding, _) in assignments {
            log("\(container) \(binding)")
        }
    }

    fileprivate func log(_ message: String) {
        if let traceStream = traceStream {
            traceStream <<< message <<< "\n"
            traceStream.flush()
        }
    }

    public func decide(_ node: DependencyResolutionNode, version: Version) {
        let term = Term(node, .exact(version))
        // FIXME: Shouldn't we check this _before_ making a decision?
        assert(term.isValidDecision(for: solution))

        solution.decide(node, at: version)
    }

    func derive(_ term: Term, cause: Incompatibility) {
        solution.derive(term, cause: cause)
    }

    public init(
        _ provider: PackageContainerProvider,
        _ delegate: DependencyResolverDelegate? = nil,
        isPrefetchingEnabled: Bool = false,
        skipUpdate: Bool = false,
        traceFile: AbsolutePath? = nil,
        traceStream: OutputByteStream? = nil
    ) {
        self.packageContainerProvider = provider
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
    public func add(_ incompatibility: Incompatibility, location: LogLocation) {
        log("incompat: \(incompatibility) \(location)")
        for package in incompatibility.terms.map({ $0.node }) {
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
    public func solve(dependencies: [Constraint], pinsMap: PinsStore.PinsMap = [:]) -> Result {
        do {
            return try .success(solve(constraints: dependencies, pinsMap: pinsMap))
        } catch {
            var error = error

            // If version solving failing, build the user-facing diagnostic.
            if let pubGrubError = error as? PubgrubError, let rootCause = pubGrubError.rootCause {
                let builder = DiagnosticReportBuilder(
                    root: root!,
                    incompatibilities: incompatibilities,
                    provider: provider
                )

                let diagnostic = builder.reportError(for: rootCause)
                error = PubgrubError.unresolvable(diagnostic)
            }

            return .error(error)
        }
    }

    struct VersionBasedConstraint {
        let node: DependencyResolutionNode
        let requirement: VersionSetSpecifier

        init(node: DependencyResolutionNode, req: VersionSetSpecifier) {
            self.node = node
            self.requirement = req
        }

        internal static func constraints(_ constraint: Constraint) -> [VersionBasedConstraint]? {
            switch constraint.requirement {
            case .versionSet(let req):
              return constraint.nodes().map { VersionBasedConstraint(node: $0, req: req) }
            case .revision:
                return nil
            case .unversioned:
                return nil
            }
        }
    }

    private func processInputs(
        with constraints: [Constraint]
    ) throws -> (
        overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)],
        rootIncompatibilities: [Incompatibility]
    ) {
        let root = self.root!

        // The list of constraints that we'll be working with. We start with the input constraints
        // and process them in two phases. The first phase finds all unversioned constraints and
        // the second phase discovers all branch-based constraints.
        var constraints = OrderedSet(constraints)

        // The list of packages that are overridden in the graph. A local package reference will
        // always override any other kind of package reference and branch-based reference will override
        // version-based reference.
        var overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)] = [:]

        // The list of version-based references reachable via local and branch-based references.
        // These are added as top-level incompatibilities since they always need to be statisfied.
        // Some of these might be overridden as we discover local and branch-based references.
        var versionBasedDependencies: [DependencyResolutionNode: [VersionBasedConstraint]] = [:]

        // Process unversioned constraints in first phase. We go through all of the unversioned packages
        // and collect them and their dependencies. This gives us the complete list of unversioned
        // packages in the graph since unversioned packages can only be refered by other
        // unversioned packages.
        while let constraint = constraints.first(where: { $0.requirement == .unversioned }) {
            constraints.remove(constraint)

            // Mark the package as overridden.
            if var existing = overriddenPackages[constraint.identifier] {
                assert(existing.version == .unversioned, "Overridden package is not unversioned: \(constraint.identifier)@\(existing.version)")
                existing.products.formUnion(constraint.products)
                overriddenPackages[constraint.identifier] = existing
            } else {
                overriddenPackages[constraint.identifier] = (version: .unversioned, products: constraint.products)
            }

            for node in constraint.nodes() {
                // Process dependencies of this package.
                //
                // We collect all version-based dependencies in a separate structure so they can
                // be process at the end. This allows us to override them when there is a non-version
                // based (unversioned/branch-based) constraint present in the graph.
                let container = try provider.getContainer(for: node.package)
                for dependency in try container.packageContainer.getUnversionedDependencies(
                    productFilter: node.productFilter()
                ) {
                    if let versionedBasedConstraints = VersionBasedConstraint.constraints(dependency) {
                        for constraint in versionedBasedConstraints {
                            versionBasedDependencies[node, default: []].append(constraint)
                        }
                    } else if !overriddenPackages.keys.contains(dependency.identifier) {
                        // Add the constraint if its not already present. This will ensure we don't
                        // end up looping infinitely due to a cycle (which are diagnosed seperately).
                        constraints.append(dependency)
                    }
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
            switch overriddenPackages[package]?.version {
                case .excluded?, .version?:
                    // These values are not possible.
                    fatalError("Unexpected value for overriden package \(package) in \(overriddenPackages)")
                case .unversioned?:
                    // This package is overridden by an unversioned package so we can ignore this constraint.
                    continue
                case .revision(let existingRevision)?:
                    // If this branch-based package was encountered before, ensure the references match.
                    if existingRevision != revision {
                        // FIXME: Improve diagnostics here.
                        throw PubgrubError.unresolvable("\(package.lastPathComponent) is required using two different revision-based requirements (\(existingRevision) and \(revision)), which is not supported")
                    } else {
                        // Otherwise, continue since we've already processed this constraint. Any cycles will be diagnosed separately.
                        continue
                    }
                case nil:
                    break
            }

            // Mark the package as overridden.
            overriddenPackages[package] = (version: .revision(revision), products: constraint.products)

            // Process dependencies of this package, similar to the first phase but branch-based dependencies
            // are not allowed to contain local/unversioned packages.
            let container = try provider.getContainer(for: package)

            // If there is a pin for this revision-based dependency, get
            // the dependencies at the pinned revision instead of using
            // latest commit on that branch. Note that if this revision-based dependency is
            // already a commit, then its pin entry doesn't matter in practice.
            let revisionForDependencies: String
            if let pin = pinsMap[package.identity], pin.state.branch == revision {
                revisionForDependencies = pin.state.revision.identifier
            } else {
                revisionForDependencies = revision
            }

            for node in constraint.nodes() {
                var unprocessedDependencies = try container.packageContainer.getDependencies(
                    at: revisionForDependencies,
                    productFilter: constraint.products
                )
                if let sharedRevision = node.revisionLock(revision: revision) {
                    unprocessedDependencies.append(sharedRevision)
                }
                for dependency in unprocessedDependencies {
                    switch dependency.requirement {
                    case .versionSet(let req):
                        for node in dependency.nodes() {
                            let versionedBasedConstraint = VersionBasedConstraint(node: node, req: req)
                            versionBasedDependencies[node, default: []].append(versionedBasedConstraint)
                        }
                    case .revision:
                        constraints.append(dependency)
                    case .unversioned:
                        throw DependencyResolverError.revisionDependencyContainsLocalPackage(
                            dependency: package.name,
                            localPackage: dependency.identifier.name
                        )
                    }
                }
            }
        }

        // At this point, we should be left with only version-based requirements in our constraints
        // list. Add them to our version-based dependency list.
        for dependency in constraints {
            switch dependency.requirement {
            case .versionSet(let req):
                for node in dependency.nodes() {
                    let versionedBasedConstraint = VersionBasedConstraint(node: node, req: req)
                    // FIXME: It would be better to record where this constraint came from, instead of just
                    // using root.
                    versionBasedDependencies[root, default: []].append(versionedBasedConstraint)
                }
            case .revision, .unversioned:
                fatalError("Unexpected revision/unversioned requirement in the constraints list: \(constraints)")
            }
        }

        // Finally, compute the root incompatibilities (which will be all version-based).
        var rootIncompatibilities: [Incompatibility] = []
        for (node, constraints) in versionBasedDependencies {
            for constraint in constraints {
                if overriddenPackages.keys.contains(constraint.node.package) { continue }

                let incompat = Incompatibility(
                    Term(root, .exact("1.0.0")),
                    Term(not: constraint.node, constraint.requirement),
                    root: root,
                    cause: .dependency(node: node))
                rootIncompatibilities.append(incompat)
            }
        }

        return (overriddenPackages, rootIncompatibilities)
    }

    /// The list of packages that are overridden in the graph. A local package reference will
    /// always override any other kind of package reference and branch-based reference will override
    /// version-based reference.
    private var overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)] = [:]

    /// Find a set of dependencies that fit the given constraints. If dependency
    /// resolution is unable to provide a result, an error is thrown.
    /// - Warning: It is expected that the root package reference has been set
    ///            before this is called.
    private func solve(
        constraints: [Constraint],
        pinsMap: PinsStore.PinsMap = [:]
    ) throws -> [(container: PackageReference, binding: BoundVersion, products: ProductFilter)] {
        let root = DependencyResolutionNode.root(package: PackageReference(
            identity: "<synthesized-root>",
            path: "<synthesized-root-path>",
            name: nil,
            kind: .root
        ))

        self.root = root
        self.pinsMap = pinsMap

        // Add the root incompatibility.
        let rootIncompatibility = Incompatibility(
            terms: [Term(not: root, .exact("1.0.0"))],
            cause: .root
        )
        add(rootIncompatibility, location: .topLevel)

        let inputs = try processInputs(with: constraints)
        self.overriddenPackages = inputs.overriddenPackages

        // Prefetch the containers if prefetching is enabled.
        if isPrefetchingEnabled {
            // We avoid prefetching packages that are overridden since
            // otherwise we'll end up creating a repository container
            // for them.
            let pins = pinsMap.values
                .map{ $0.packageRef }
                .filter{ !overriddenPackages.keys.contains($0) }
            self.provider.prefetch(containers: pins)
        }

        // Add all the root incompatibilities.
        for incompat in inputs.rootIncompatibilities {
            add(incompat, location: .topLevel)
        }

        // Decide root at v1.
        decide(root, version: "1.0.0")

        try run()

        let decisions = solution.assignments.filter { $0.isDecision }
        var flattenedAssignments: [PackageReference: (binding: BoundVersion, products: ProductFilter)] = [:]
        for assignment in decisions {
            if assignment.term.node == root {
                continue
            }

            let boundVersion: BoundVersion
            switch assignment.term.requirement {
            case .exact(let version):
                boundVersion = .version(version)
            case .range, .any, .empty, .ranges:
                fatalError("unexpected requirement value for assignment \(assignment.term)")
            }

            let products = assignment.term.node.productFilter()

            let container = try provider.getContainer(for: assignment.term.node.package)
            let identifier = try container.packageContainer.getUpdatedIdentifier(at: boundVersion)

            if var existing = flattenedAssignments[identifier] {
                assert(existing.binding == boundVersion, "Two products in one package resolved to different versions: \(existing.products)@\(existing.binding) vs \(products)@\(boundVersion)")
                existing.products.formUnion(products)
                flattenedAssignments[identifier] = existing
            } else {
                flattenedAssignments[identifier] = (binding: boundVersion, products: products)
            }
        }
        var finalAssignments: [DependencyResolver.Binding]
            = flattenedAssignments.keys.sorted(by: { $0.name < $1.name }).map { package in
                let details = flattenedAssignments[package]!
                return (container: package, binding: details.binding, products: details.products)
        }

        // Add overriden packages to the result.
        for (package, override) in overriddenPackages {
            let container = try provider.getContainer(for: package)
            let identifier = try container.packageContainer.getUpdatedIdentifier(at: override.version)
            finalAssignments.append((identifier, override.version, override.products))
        }

        log(finalAssignments)

        return finalAssignments
    }

    /// Perform unit propagation, resolving conflicts if necessary and making
    /// decisions if nothing else is left to be done.
    /// After this method returns `solution` is either populated with a list of
    /// final version assignments or an error is thrown.
    func run() throws {
        var next: DependencyResolutionNode? = root
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
    public func propagate(_ node: DependencyResolutionNode) throws {
        var changed: OrderedSet<DependencyResolutionNode> = [node]

        while !changed.isEmpty {
            let package = changed.removeFirst()
            loop: for incompatibility in positiveIncompatibilities(for: package)?.reversed() ?? [] {
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
        derive(unsatisfiedTerm.inverse, cause: incompatibility)

        return .almostSatisfied(node: unsatisfiedTerm.node)
    }

    enum PropagationResult {
        case conflict
        case almostSatisfied(node: DependencyResolutionNode)
        case none
    }

    public func _resolve(conflict: Incompatibility) throws -> Incompatibility {
        log("conflict: \(conflict)")
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
                    let mostRecentSatisfierIdx = solution.assignments.firstIndex(of: _mostRecentSatisfier)!
                    let satisfierIdx = solution.assignments.firstIndex(of: satisfier)!

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
            newTerms += priorCause.terms.filter({ $0.node != _mostRecentSatisfier.term.node })

            if let _difference = difference {
                newTerms.append(_difference.inverse)
            }

            incompatibility = Incompatibility(
                OrderedSet(newTerms),
                root: root!,
                cause: .conflict(cause: .init(conflict: incompatibility, other: priorCause)))
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
        return incompatibility.terms.isEmpty || (incompatibility.terms.count == 1 && incompatibility.terms.first?.node == root)
    }

    public func makeDecision() throws -> DependencyResolutionNode? {
        let undecided = solution.undecided

        // If there are no more undecided terms, version solving is complete.
        guard !undecided.isEmpty else {
            return nil
        }

        // Prefer packages with least number of versions that fit the current requirements so we
        // get conflicts (if any) sooner.
        let pkgTerm = try undecided.min {
            let count1 = try provider.getContainer(for: $0.node.package).versionCount($0.requirement)
            let count2 = try provider.getContainer(for: $1.node.package).versionCount($1.requirement)
            return count1 < count2
        }!

        let container = try provider.getContainer(for: pkgTerm.node.package)
        // Get the best available version for this package.
        guard let version = try container.getBestAvailableVersion(for: pkgTerm) else {
            add(Incompatibility(pkgTerm, root: root!, cause: .noAvailableVersion), location: .decisionMaking)
            return pkgTerm.node
        }

        // Add all of this version's dependencies as incompatibilities.
        let depIncompatibilities = try container.incompatibilites(
            at: version,
            node: pkgTerm.node,
            overriddenPackages: overriddenPackages,
            root: root!)

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
                $0.node == pkgTerm.node || solution.satisfies($0)
            }
        }

        // Decide this version if there was no conflict with its dependencies.
        if !haveConflict {
            log("decision: \(pkgTerm.node.package)@\(version)")
            decide(pkgTerm.node, version: version)
        }

        return pkgTerm.node
    }
}

private final class DiagnosticReportBuilder {
    let rootNode: DependencyResolutionNode
    let incompatibilities: [DependencyResolutionNode: [Incompatibility]]

    private var lines: [(String, Int)] = []
    private var derivations: [Incompatibility: Int] = [:]
    private var lineNumbers: [Incompatibility: Int] = [:]
    private let provider: ContainerProvider

    init(root: DependencyResolutionNode, incompatibilities: [DependencyResolutionNode: [Incompatibility]], provider: ContainerProvider) {
        self.rootNode = root
        self.incompatibilities = incompatibilities
        self.provider = provider
    }

    func reportError(for incompatibility: Incompatibility) -> String {
        /// Populate `derivations`.
        func countDerivations(_ i: Incompatibility) {
            derivations[i, default: 0] += 1
            if case .conflict(let cause) = i.cause {
                countDerivations(cause.conflict)
                countDerivations(cause.other)
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
        case .dependency(node: _):
            assert(incompatibility.terms.count == 2)
            let depender = incompatibility.terms.first!
            let dependee = incompatibility.terms.last!
            assert(depender.isPositive)
            assert(!dependee.isPositive)

            let dependerDesc = description(for: depender, normalizeRange: true)
            let dependeeDesc = description(for: dependee)
            return "\(dependerDesc) depends on \(dependeeDesc)"
        case .noAvailableVersion:
            assert(incompatibility.terms.count == 1)
            let term = incompatibility.terms.first!
            assert(term.isPositive)
            return "no versions of \(term.node.nameForDiagnostics()) match the requirement \(term.requirement)"
        case .root:
            // FIXME: This will never happen I think.
            assert(incompatibility.terms.count == 1)
            let term = incompatibility.terms.first!
            assert(term.isPositive)
            return "\(term.node.nameForDiagnostics()) is \(term.requirement)"
        case .conflict:
            break
        case .versionBasedDependencyContainsUnversionedDependency(let versionedDependency, let unversionedDependency):
            return "package \(versionedDependency) is required using a version-based requirement and it depends on unversion package \(unversionedDependency)"
        case .incompatibleToolsVersion:
            let term = incompatibility.terms.first!
            return "\(description(for: term, normalizeRange: true)) contains incompatible tools version"
        }

        if isFailure(incompatibility) {
            return "version solving failed"
        }

        let terms = incompatibility.terms
        if terms.count == 1 {
            let term = terms.first!
            let prefix = hasEffectivelyAnyRequirement(term) ? term.node.nameForDiagnostics() : description(for: term, normalizeRange: true)
            return "\(prefix) is " + (term.isPositive ? "forbidden" : "required")
        } else if terms.count == 2 {
            let term1 = terms.first!
            let term2 = terms.last!
            if term1.isPositive == term2.isPositive {
                if term1.isPositive {
                    return "\(term1.node.nameForDiagnostics()) is incompatible with \(term2.node.nameForDiagnostics())";
                } else {
                    return "either \(term1.node.nameForDiagnostics()) or \(term2)"
                }
            }
        }

        let positive = terms.filter{ $0.isPositive }.map{ description(for: $0) }
        let negative = terms.filter{ !$0.isPositive }.map{ description(for: $0) }
        if !positive.isEmpty && !negative.isEmpty {
            if positive.count == 1 {
                let positiveTerm = terms.first{ $0.isPositive }!
                return "\(description(for: positiveTerm, normalizeRange: true)) requires \(negative.joined(separator: " or "))";
            } else {
                return "if \(positive.joined(separator: " and ")) then \(negative.joined(separator: " or "))";
            }
        } else if !positive.isEmpty {
            return "one of \(positive.joined(separator: " or ")) must be true"
        } else {
            return "one of \(negative.joined(separator: " or ")) must be true"
        }
    }

    /// Returns true if the requirement on this term is effectively "any" because of either the actual
    /// `any` requirement or because the version range is large enough to fit all current available versions.
    private func hasEffectivelyAnyRequirement(_ term: Term) -> Bool {
        switch term.requirement {
        case .any:
            return true
        case .empty, .exact, .ranges:
            return false
        case .range(let range):
            guard let container = try? provider.getContainer(for: term.node.package) else {
                return false
            }
            let bounds = container.computeBounds(for: range)
            return !bounds.includesLowerBound && !bounds.includesUpperBound
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
        return incompatibility.terms.count == 1 && incompatibility.terms.first?.node.package.identity == "<synthesized-root>"
    }

    private func description(for term: Term, normalizeRange: Bool = false) -> String {
        let name = term.node.nameForDiagnostics()

        switch term.requirement {
        case .any: return "every version of \(name)"
        case .empty: return "no version of \(name)"
        case .exact(let version):
            // For the root package, don't output the useless version 1.0.0.
            if term.node == rootNode {
                return "root"
            }
            return "\(name) \(version)"
        case .range(let range):
            guard normalizeRange, let container = try? provider.getContainer(for: term.node.package) else {
                return "\(name) \(range.description)"
            }

            switch container.computeBounds(for: range) {
            case (true, true):
                return "\(name) \(range.description)"
            case (false, false):
                return "every version of \(name)"
            case (true, false):
                return "\(name) >=\(range.lowerBound)"
            case (false, true):
                return "\(name) <\(range.upperBound)"
            }
        case .ranges(let ranges):
            let ranges = "{" + ranges.map{
                if $0.lowerBound == $0.upperBound {
                    return $0.lowerBound.description
                }
                return $0.lowerBound.description + "..<" + $0.upperBound.description
            }.joined(separator: ", ") + "}"
            return "\(name) \(ranges)"
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

// MARK:- Container Management

/// A container for an individual package. This enhances PackageContainer to add PubGrub specific
/// logic which is mostly related to computing incompatibilities at a particular version.
private final class PubGrubPackageContainer {

    /// The underlying package container.
    let packageContainer: PackageContainer

    /// Reference to the pins map.
    let pinsMap: PinsStore.PinsMap

    var package: PackageReference {
        packageContainer.identifier
    }

    init(_ container: PackageContainer, pinsMap: PinsStore.PinsMap) {
        self.packageContainer = container
        self.pinsMap = pinsMap
    }

    /// Returns the pinned version for this package, if any.
    var pinnedVersion: Version? {
        return pinsMap[packageContainer.identifier.identity]?.state.version
    }

    /// Returns the numbers of versions that are satisfied by the given version requirement.
    func versionCount(_ requirement: VersionSetSpecifier) -> Int {
        if let pinnedVersion = self.pinnedVersion, requirement.contains(pinnedVersion) {
            return 1
        }
        return packageContainer.reversedVersions.filter(requirement.contains).count
    }

    /// Computes the bounds of the given range against the versions available in the package.
    ///
    /// `includesLowerBound` is `false` if range's lower bound is less than or equal to the lowest available version.
    /// Similarly, `includesUpperBound` is `false` if range's upper bound is greater than or equal to the highest available version.
    func computeBounds(for range: Range<Version>) -> (includesLowerBound: Bool, includesUpperBound: Bool) {
        var includeLowerBound = true
        var includeUpperBound = true

        let versions = packageContainer.reversedVersions

        if let last = versions.last, range.lowerBound < last {
            includeLowerBound = false
        }

        if let first = versions.first, range.upperBound > first {
            includeUpperBound = false
        }

        return (includeLowerBound, includeUpperBound)
    }

    /// Returns the best available version for a given term.
    func getBestAvailableVersion(for term: Term) throws -> Version? {
        assert(term.isPositive, "Expected term to be positive")
        var versionSet = term.requirement

        // Restrict the selection to the pinned version if is allowed by the current requirements.
        if let pinnedVersion = self.pinnedVersion {
            if versionSet.contains(pinnedVersion) {
                versionSet = .exact(pinnedVersion)
            }
        }

        // Return the highest version that is allowed by the input requirement.
        return packageContainer.reversedVersions.first{ versionSet.contains($0) }
    }

    /// Compute the bounds of incompatible tools version starting from the given version.
    private func computeIncompatibleToolsVersionBounds(fromVersion: Version) -> VersionSetSpecifier {
        assert(!packageContainer.isToolsVersionCompatible(at: fromVersion))
        let versions: [Version] = packageContainer.reversedVersions.reversed()

        // This is guaranteed to be present.
        let idx = versions.firstIndex(of: fromVersion)!

        var lowerBound = fromVersion
        var upperBound = fromVersion

        for version in versions.dropFirst(idx + 1) {
            let isToolsVersionCompatible = packageContainer.isToolsVersionCompatible(at: version)
            if isToolsVersionCompatible {
                break
            }
            upperBound = version
        }

        for version in versions.dropLast(versions.count - idx).reversed() {
            let isToolsVersionCompatible = packageContainer.isToolsVersionCompatible(at: version)
            if isToolsVersionCompatible {
                break
            }
            lowerBound = version
        }

        // If lower and upper bounds didn't change then this is the sole incompatible version.
        if lowerBound == upperBound {
            return .exact(lowerBound)
        }

        // If lower bound is the first version then we can use 0 as the sentinel. This
        // will end up producing a better diagnostic since we can omit the lower bound.
        if lowerBound == versions.first {
            lowerBound = "0.0.0"
        }

        if upperBound == versions.last {
            // If upper bound is the last version then we can use the next major version as the sentinel.
            // This will end up producing a better diagnostic since we can omit the upper bound.
            upperBound = Version(upperBound.major + 1, 0, 0)
        } else {
            // Use the next patch since the upper bound needs to be inclusive here.
            upperBound = upperBound.nextPatch()
        }
        return .range(lowerBound..<upperBound.nextPatch())
    }

    /// Returns the incompatibilities of a package at the given version.
    func incompatibilites(
        at version: Version,
        node: DependencyResolutionNode,
        overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)],
        root: DependencyResolutionNode
    ) throws -> [Incompatibility] {
        // FIXME: It would be nice to compute bounds for this as well.
        if !packageContainer.isToolsVersionCompatible(at: version) {
            let requirement = computeIncompatibleToolsVersionBounds(fromVersion: version)
            return [Incompatibility(Term(node, requirement), root: root, cause: .incompatibleToolsVersion)]
        }

        var unprocessedDependencies = try packageContainer.getDependencies(at: version, productFilter: node.productFilter())
        if let sharedVersion = node.versionLock(version: version) {
            unprocessedDependencies.append(sharedVersion)
        }
        var dependencies: [PackageContainerConstraint] = []
        for dep in unprocessedDependencies {
            // Version-based packages are not allowed to contain unversioned dependencies.
            guard case .versionSet = dep.requirement else {
                let cause: Incompatibility.Cause = .versionBasedDependencyContainsUnversionedDependency(
                    versionedDependency: package.identity,
                    unversionedDependency: dep.identifier.identity)
                return [Incompatibility(Term(node, .exact(version)), root: root, cause: cause)]
            }

            // Skip if this package is overriden.
            if overriddenPackages.keys.contains(dep.identifier) {
                continue
            }

            // Skip if we already emitted incompatibilities for this dependency such that the selected
            // falls within the previously computed bounds.
            if emittedIncompatibilities[dep.identifier]?.contains(version) != true {
                dependencies.append(dep)
            }
        }

        // Emit the dependencies at the pinned version if we haven't emitted anything else yet.
        if version == pinnedVersion && emittedIncompatibilities.isEmpty {
            // We don't need to emit anything if we already emitted the incompatibilities at the
            // pinned version.
            if self.emittedPinnedVersionIncompatibilities { return [] }

            self.emittedPinnedVersionIncompatibilities = true

            // Since the pinned version is most likely to succeed, we don't compute bounds for its
            // incompatibilities.
            return Array(dependencies.map({ (constraint: PackageContainerConstraint) -> [Incompatibility] in
                guard case .versionSet(let vs) = constraint.requirement else { fatalError("Unexpected unversioned requirement: \(constraint)") }
                return constraint.nodes().map { dependencyNode in
                    var terms: OrderedSet<Term> = []
                    terms.append(Term(node, .exact(version)))
                    terms.append(Term(not: dependencyNode, vs))
                    return Incompatibility(terms, root: root, cause: .dependency(node: node))
                }
            }).joined())
        }

        let (lowerBounds, upperBounds) = computeBounds(dependencies, from: version, products: node.productFilter())

        return dependencies.map { dependency in
            var terms: OrderedSet<Term> = []
            let lowerBound = lowerBounds[dependency.identifier] ?? "0.0.0"
            let upperBound = upperBounds[dependency.identifier] ?? Version(version.major + 1, 0, 0)
            assert(lowerBound < upperBound)

            // We only have version-based requirements at this point.
            guard case .versionSet(let vs) = dependency.requirement else { fatalError("Unexpected unversioned requirement: \(dependency)") }

            for dependencyNode in dependency.nodes() {
              let requirement: VersionSetSpecifier = .range(lowerBound..<upperBound)
              terms.append(Term(node, requirement))
              terms.append(Term(not: dependencyNode, vs))

              // Make a record for this dependency so we don't have to recompute the bounds when the selected version falls within the bounds.
              emittedIncompatibilities[dependency.identifier] = requirement.union(emittedIncompatibilities[dependency.identifier] ?? .empty)
            }

            return Incompatibility(terms, root: root, cause: .dependency(node: node))
        }
    }

    /// The map of dependencies to version set that indicates the versions that have had their
    /// incompatibilities emitted.
    private var emittedIncompatibilities: [PackageReference: VersionSetSpecifier] = [:]

    /// Whether we've emitted the incompatibilities for the pinned versions.
    private var emittedPinnedVersionIncompatibilities: Bool = false

    /// Method for computing bounds of the given dependencies.
    ///
    /// This will return a dictionary which contains mapping of a package dependency to its bound.
    /// If a dependency is absent in the dictionary, it is present in all versions of the package
    /// above or below the given version. As with regular version ranges, the lower bound is
    /// inclusive and the upper bound is exclusive.
    private func computeBounds(
        _ dependencies: [PackageContainerConstraint],
        from fromVersion: Version,
        products: ProductFilter
    ) -> (lowerBounds: [PackageReference: Version], upperBounds: [PackageReference: Version]) {
        func computeBounds(with versionsToIterate: AnyCollection<Version>, upperBound: Bool) -> [PackageReference: Version] {
            var result: [PackageReference: Version] = [:]
            var prev = fromVersion

            for version in versionsToIterate {
                let bound = upperBound ? version : prev

                // If we hit a version which doesn't have a compatible tools version then that's the boundary.
                let isToolsVersionCompatible = packageContainer.isToolsVersionCompatible(at: version)

                // Get the dependencies at this version.
                let currentDependencies = (try? packageContainer.getDependencies(at: version, productFilter: products)) ?? []

                // Record this version as the bound for our list of dependencies, if appropriate.
                for dependency in dependencies where !result.keys.contains(dependency.identifier) {
                    // Record the bound if the tools version isn't compatible at the current version.
                    if !isToolsVersionCompatible {
                        result[dependency.identifier] = bound
                    } else if currentDependencies.first(where: { $0.identifier == dependency.identifier }) != dependency {
                        // Record this version as the bound if we're finding upper bounds since
                        // upper bound is exclusive and record the previous version if we're
                        // finding the lower bound since that is inclusive.
                        result[dependency.identifier] = bound
                    }
                }

                // We're done if we found bounds for all of our dependencies.
                if result.count == dependencies.count {
                    break
                }

                prev = version
            }

            return result
        }

        let versions: [Version] = packageContainer.reversedVersions.reversed()

        // This is guaranteed to be present.
        let idx = versions.firstIndex(of: fromVersion)!

        // Compute upper and lower bounds for the dependencies.
        let upperBounds = computeBounds(with: AnyCollection(versions.dropFirst(idx + 1)), upperBound: true)
        let lowerBounds = computeBounds(with: AnyCollection(versions.dropLast(versions.count - idx).reversed()), upperBound: false)

        return (lowerBounds, upperBounds)
    }
}

/// An utility class around PackageContainerProvider that allows "prefetching" the containers
/// in parallel. The basic idea is to kick off container fetching before starting the resolution
/// by using the list of URLs from the Package.resolved file.
private final class ContainerProvider {
    /// The actual package container provider.
    let provider: PackageContainerProvider

    /// Wheather to perform update (git fetch) on existing cloned repositories or not.
    let skipUpdate: Bool

    /// Reference to the pins store.
    let pinsMap: PinsStore.PinsMap

    init(_ provider: PackageContainerProvider, skipUpdate: Bool, pinsMap: PinsStore.PinsMap) {
        self.provider = provider
        self.skipUpdate = skipUpdate
        self.pinsMap = pinsMap
    }

    /// Condition for container management structures.
    private let fetchCondition = Condition()

    /// The list of fetched containers.
    private var _fetchedContainers: [PackageReference: Result<PubGrubPackageContainer, Error>] = [:]

    /// The set of containers requested so far.
    private var _prefetchingContainers: Set<PackageReference> = []

    /// Get the container for the given identifier, loading it if necessary.
    func getContainer(for identifier: PackageReference) throws -> PubGrubPackageContainer {
        return try fetchCondition.whileLocked {
            // Return the cached container, if available.
            if let container = _fetchedContainers[identifier] {
                return try container.get()
            }

            // If this container is being prefetched, wait for that to complete.
            while _prefetchingContainers.contains(identifier) {
                fetchCondition.wait()
            }

            // The container may now be available in our cache if it was prefetched.
            if let container = _fetchedContainers[identifier] {
                return try container.get()
            }

            // Otherwise, fetch the container synchronously.
            let container = try await { provider.getContainer(for: identifier, skipUpdate: skipUpdate, completion: $0) }
            let pubGrubContainer = PubGrubPackageContainer(container, pinsMap: pinsMap)
            self._fetchedContainers[identifier] = .success(pubGrubContainer)
            return pubGrubContainer
        }
    }

    /// Starts prefetching the given containers.
    func prefetch(containers identifiers: [PackageReference]) {
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
                    DispatchQueue.global().async {
                        self.fetchCondition.whileLocked {
                            // Update the structures and signal any thread waiting
                            // on prefetching to finish.
                            let pubGrubContainer = container.map {
                                PubGrubPackageContainer($0, pinsMap: self.pinsMap)
                            }
                            self._fetchedContainers[identifier] = pubGrubContainer
                            self._prefetchingContainers.remove(identifier)
                            self.fetchCondition.signal()
                        }
                    }
                }
            }
        }
    }
}

// MARK:- Misc Extensions

extension VersionSetSpecifier {
    fileprivate var isExact: Bool {
        switch self {
        case .any, .empty, .range, .ranges:
            return false
        case .exact:
            return true
        }
    }
}

extension PackageRequirement {
    fileprivate var isRevision: Bool {
        switch self {
        case .versionSet, .unversioned:
            return false
        case .revision:
            return true
        }
    }
}

extension PackageReference {
    /// Returns the last path component of the path (without .git suffix, if present).
    fileprivate var lastPathComponent: String {
        return String(path.split(separator: "/").last!).spm_dropGitSuffix()
    }
}
