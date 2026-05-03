//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import class Foundation.NSLock
import OrderedCollections
import PackageModel

import struct TSCUtility.Version

/// The solver that is able to transitively resolve a set of package constraints
/// specified by a root package.
public struct PubGrubDependencyResolver {
    /// The type of the constraints the resolver operates on.
    public typealias Constraint = PackageContainerConstraint

    /// the mutable state that get computed
    internal final class State {
        /// The root package reference.
        let root: DependencyResolutionNode

        /// The list of packages that are overridden in the graph. A local package reference will
        /// always override any other kind of package reference and branch-based reference will override
        /// version-based reference.
        let overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)]

        /// A collection of all known incompatibilities matched to the packages they
        /// refer to. This means an incompatibility can occur several times.
        public private(set) var incompatibilities: [DependencyResolutionNode: [Incompatibility]] = [:]

        /// The current best guess for a solution satisfying all requirements.
        public private(set) var solution: PartialSolution

        private let lock = NSLock()

        init(root: DependencyResolutionNode,
             overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)] = [:],
             solution: PartialSolution = PartialSolution())
        {
            self.root = root
            self.overriddenPackages = overriddenPackages
            self.solution = solution
        }

        func addIncompatibility(_ incompatibility: Incompatibility, at location: LogLocation) {
            self.lock.withLock {
                // log("incompat: \(incompatibility) \(location)")
                for package in incompatibility.terms.map(\.node) {
                    if let incompats = self.incompatibilities[package] {
                        if !incompats.contains(incompatibility) {
                            self.incompatibilities[package]!.append(incompatibility)
                        }
                    } else {
                        self.incompatibilities[package] = [incompatibility]
                    }
                }
            }
        }

        /// Find all incompatibilities containing a positive term for a given package.
        func positiveIncompatibilities(for node: DependencyResolutionNode) -> [Incompatibility]? {
            self.lock.withLock {
                guard let all = self.incompatibilities[node] else {
                    return nil
                }
                return all.filter {
                    $0.terms.first { $0.node == node }!.isPositive
                }
            }
        }

        func decide(_ node: DependencyResolutionNode, at version: Version) {
            let term = Term(node, .exact(version))
            self.lock.withLock {
                assert(term.isValidDecision(for: self.solution))
                self.solution.decide(node, at: version)
            }
        }

        func derive(_ term: Term, cause: Incompatibility) {
            self.lock.withLock {
                self.solution.derive(term, cause: cause)
            }
        }

        func backtrack(toDecisionLevel: Int) {
            self.lock.withLock {
                self.solution.backtrack(toDecisionLevel: toDecisionLevel)
            }
        }
    }

    /// `Package.resolved` representation.
    private let resolvedPackages: ResolvedPackagesStore.ResolvedPackages

    /// The container provider used to load package containers.
    private let provider: ContainerProvider

    /// Reference to the package container provider.
    private let packageContainerProvider: PackageContainerProvider

    /// Should resolver prefetch the containers.
    private let prefetchBasedOnResolvedFile: Bool

    /// Update containers while fetching them.
    private let skipDependenciesUpdates: Bool

    /// Resolver delegate
    private let delegate: DependencyResolverDelegate?

    @available(*,
        deprecated,
        renamed: "init(provider:resolvedPackages:skipDependenciesUpdates:prefetchBasedOnResolvedFile:observabilityScope:delegate:)",
        message: "Renamed for consistency with the actual name of the feature"
    )
    @_disfavoredOverload
    public init(
        provider: PackageContainerProvider,
        pins: ResolvedPackagesStore.ResolvedPackages = [:],
        skipDependenciesUpdates: Bool = false,
        prefetchBasedOnResolvedFile: Bool = false,
        observabilityScope: ObservabilityScope,
        delegate: DependencyResolverDelegate? = nil
    ) {
        self.init(
            provider: provider,
            resolvedPackages: pins,
            skipDependenciesUpdates: skipDependenciesUpdates,
            prefetchBasedOnResolvedFile: prefetchBasedOnResolvedFile,
            observabilityScope: observabilityScope,
            delegate: delegate
        )
    }

    public init(
        provider: PackageContainerProvider,
        resolvedPackages: ResolvedPackagesStore.ResolvedPackages = [:],
        skipDependenciesUpdates: Bool = false,
        prefetchBasedOnResolvedFile: Bool = false,
        observabilityScope: ObservabilityScope,
        delegate: DependencyResolverDelegate? = nil
    ) {
        self.packageContainerProvider = provider
        self.resolvedPackages = resolvedPackages
        self.skipDependenciesUpdates = skipDependenciesUpdates
        self.prefetchBasedOnResolvedFile = prefetchBasedOnResolvedFile
        self.provider = ContainerProvider(
            provider: self.packageContainerProvider,
            skipUpdate: self.skipDependenciesUpdates,
            resolvedPackages: self.resolvedPackages,
            observabilityScope: observabilityScope
        )
        self.delegate = delegate
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    public func solve(constraints: [Constraint]) async -> Result<[DependencyResolverBinding], Error> {
        // the graph resolution root
        let root: DependencyResolutionNode
        if constraints.count == 1, let constraint = constraints.first, constraint.package.kind.isRoot {
            // root level package, use it as our resolution root
            root = .root(package: constraint.package, enabledTraits: constraint.enabledTraits)
        } else {
            // more complex setup requires a synthesized root
            root = .root(
                package: .root(
                    identity: .plain("<synthesized-root>"),
                    path: .root
                ),
                enabledTraits: ["default"]
            )
        }

        do {
            // strips state
            let bindings = try await self.solve(root: root, constraints: constraints).bindings
            return .success(bindings)
        } catch {
            // If version solving failing, build the user-facing diagnostic.
            if let pubGrubError = error as? PubGrubError, let rootCause = pubGrubError.rootCause, let incompatibilities = pubGrubError.incompatibilities {
                do {
                    var builder = DiagnosticReportBuilder(
                        root: root,
                        incompatibilities: incompatibilities,
                        provider: self.provider
                    )
                    let diagnostic = try await builder.makeErrorReport(for: rootCause)
                    return .failure(PubGrubError.unresolvable(diagnostic))
                } catch {
                    // failed to construct the report, will report the original error
                    return .failure(error)
                }
            }
            return .failure(error)
        }
    }

    /// Find a set of dependencies that fit the given constraints. If dependency
    /// resolution is unable to provide a result, an error is thrown.
    /// - Warning: It is expected that the root package reference has been set  before this is called.
    internal func solve(root: DependencyResolutionNode, constraints: [Constraint]) async throws -> (bindings: [DependencyResolverBinding], state: State) {
        // first process inputs
        let inputs = try await self.processInputs(root: root, with: constraints)

        // Prefetch the containers if prefetching is enabled.
        if self.prefetchBasedOnResolvedFile {
            // We avoid prefetching packages that are overridden since
            // otherwise we'll end up creating a repository container
            // for them.
            let resolvedPackageReferences = self.resolvedPackages.values
                .map(\.packageRef)
                .filter { !inputs.overriddenPackages.keys.contains($0) }
            self.provider.prefetch(containers: resolvedPackageReferences)
        }

        let state = State(root: root, overriddenPackages: inputs.overriddenPackages)

        // Decide root at v1.
        state.decide(state.root, at: "1.0.0")

        // Add the root incompatibility.
        state.addIncompatibility(Incompatibility(terms: [Term(not: root, .exact("1.0.0"))], cause: .root), at: .topLevel)

        // Add inputs root incompatibilities.
        for incompatibility in inputs.rootIncompatibilities {
            state.addIncompatibility(incompatibility, at: .topLevel)
        }

        try await self.run(state: state)

        let decisions = state.solution.assignments.filter(\.isDecision)
        var flattenedAssignments: [PackageReference: (binding: BoundVersion, products: ProductFilter)] = [:]
        for assignment in decisions {
            if assignment.term.node == state.root {
                continue
            }

            let boundVersion: BoundVersion
            switch assignment.term.requirement {
            case .exact(let version):
                boundVersion = .version(version)
            case .range, .any, .empty, .ranges:
                throw InternalError("unexpected requirement value for assignment \(assignment.term)")
            }

            let products = assignment.term.node.productFilter
            let container = try await withCheckedThrowingContinuation { continuation in
                self.provider.getContainer(
                    for: assignment.term.node.package,
                    completion: {
                        continuation.resume(with: $0)
                    }
                )
            }
            let updatePackage = try await container.underlying.loadPackageReference(at: boundVersion)

            if var existing = flattenedAssignments[updatePackage] {
                guard existing.binding == boundVersion else {
                    throw InternalError("Two products in one package resolved to different versions: \(existing.products)@\(existing.binding) vs \(products)@\(boundVersion)")
                }
                existing.products.formUnion(products)
                flattenedAssignments[updatePackage] = existing
            } else {
                flattenedAssignments[updatePackage] = (binding: boundVersion, products: products)
            }
        }
        var finalAssignments: [DependencyResolverBinding]
            = flattenedAssignments.keys.sorted(by: { $0.deprecatedName < $1.deprecatedName }).map { package in
                let details = flattenedAssignments[package]!
                return .init(package: package, boundVersion: details.binding, products: details.products)
            }

        // Add overridden packages to the result.
        for (package, override) in state.overriddenPackages {
            let container = try await withCheckedThrowingContinuation { continuation in
                self.provider.getContainer(for: package, completion: {
                    continuation.resume(with: $0)
                })
            }
            let updatePackage = try await container.underlying.loadPackageReference(at: override.version)
            finalAssignments.append(.init(
                    package: updatePackage,
                    boundVersion: override.version,
                    products: override.products
            ))
        }

        self.delegate?.solved(result: finalAssignments)

        return (finalAssignments, state)
    }

    private func processInputs(
        root: DependencyResolutionNode,
        with constraints: [Constraint]
    ) async throws -> (
        overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)],
        rootIncompatibilities: [Incompatibility]
    ) {
        // The list of constraints that we'll be working with. We start with the input constraints
        // and process them in two phases. The first phase finds all unversioned constraints and
        // the second phase discovers all branch-based constraints.
        var constraints = OrderedCollections.OrderedSet(constraints)

        // The list of packages that are overridden in the graph. A local package reference will
        // always override any other kind of package reference and branch-based reference will override
        // version-based reference.
        var overriddenPackages: [PackageReference: (version: BoundVersion, products: ProductFilter)] = [:]

        // The list of version-based references reachable via local and branch-based references.
        // These are added as top-level incompatibilities since they always need to be satisfied.
        // Some of these might be overridden as we discover local and branch-based references.
        var versionBasedDependencies = OrderedCollections.OrderedDictionary<DependencyResolutionNode, [VersionBasedConstraint]>()

        // Process unversioned constraints in the first phase. Each iteration of the outer
        // loop drains the wavefront of currently-known unversioned constraints and fetches
        // their containers and dependencies in parallel; new unversioned constraints
        // discovered in the wave are picked up by the next iteration.
        //
        // Order is preserved by:
        //   1. Updating `overriddenPackages` for every wave member up front, sequentially
        //      in wave order, so that downstream classification observes the full
        //      wave's overrides.
        //   2. Merging the per-wave-member discoveries back into
        //      `versionBasedDependencies` and `constraints` sequentially in wave order
        //      after parallel fetches complete. This yields the same insertion order
        //      into both structures as the original sequential implementation.
        while true {
            let wave = constraints.filter { $0.requirement == .unversioned }
            if wave.isEmpty { break }
            for constraint in wave { constraints.remove(constraint) }

            for constraint in wave {
                if var existing = overriddenPackages[constraint.package] {
                    guard existing.version == .unversioned else {
                        throw InternalError("Overridden package is not unversioned: \(constraint.package)@\(existing.version)")
                    }
                    existing.products.formUnion(constraint.products)
                    overriddenPackages[constraint.package] = existing
                } else {
                    overriddenPackages[constraint.package] = (version: .unversioned, products: constraint.products)
                }
            }

            let perConstraintDeps = try await withThrowingTaskGroup(
                of: (Int, [(DependencyResolutionNode, [Constraint])]).self
            ) { group in
                for (i, constraint) in wave.enumerated() {
                    group.addTask {
                        var nodeDeps: [(DependencyResolutionNode, [Constraint])] = []
                        for node in constraint.nodes() {
                            let container = try await withCheckedThrowingContinuation { continuation in
                                self.provider.getContainer(
                                    for: node.package,
                                    completion: { continuation.resume(with: $0) }
                                )
                            }
                            let deps = try await container.underlying.getUnversionedDependencies(
                                productFilter: node.productFilter,
                                node.enabledTraits
                            )
                            nodeDeps.append((node, deps))
                        }
                        return (i, nodeDeps)
                    }
                }
                var results = [[(DependencyResolutionNode, [Constraint])]](
                    repeating: [],
                    count: wave.count
                )
                for try await (i, deps) in group {
                    results[i] = deps
                }
                return results
            }

            for nodeDepsList in perConstraintDeps {
                for (node, deps) in nodeDepsList {
                    for dependency in deps {
                        if let versionedBasedConstraints = VersionBasedConstraint.constraints(dependency) {
                            for vbc in versionedBasedConstraints {
                                versionBasedDependencies[node, default: []].append(vbc)
                            }
                        } else if !overriddenPackages.keys.contains(dependency.package) {
                            // Add the constraint if it's not already present. This will ensure we don't
                            // end up looping infinitely due to a cycle (which are diagnosed separately).
                            constraints.append(dependency)
                        }
                    }
                }
            }
        }

        // Process revision-based constraints in the second phase. Same wave structure
        // as phase 1, but the override checks (which can short-circuit a constraint
        // via `continue` or throw on a revision conflict) must run sequentially because
        // each successful check writes into `overriddenPackages` and a subsequent wave
        // member may need to observe that write to be skipped.
        while true {
            let pending = constraints.filter { $0.requirement.isRevision }
            if pending.isEmpty { break }

            var wave: [(constraint: Constraint, revision: String, revisionForDependencies: String)] = []
            for constraint in pending {
                constraints.remove(constraint)

                guard case .revision(let revision) = constraint.requirement else {
                    throw InternalError("Expected revision requirement")
                }
                let package = constraint.package

                switch overriddenPackages[package]?.version {
                case .excluded?, .version?:
                    throw InternalError("Unexpected value for overridden package \(package) in \(overriddenPackages)")
                case .unversioned?:
                    // Already overridden by an unversioned constraint; skip.
                    continue
                case .revision(let existingRevision, let branch)?:
                    if (branch ?? existingRevision) != revision {
                        throw PubGrubError.unresolvable("\(package.identity) is required using two different revision-based requirements (\(existingRevision) and \(revision)), which is not supported")
                    } else {
                        continue
                    }
                case nil:
                    break
                }

                let revisionForDependencies: String
                if case .branch(revision, let pinRevision) = self.resolvedPackages[package.identity]?.state {
                    revisionForDependencies = pinRevision
                    overriddenPackages[package] = (version: .revision(revisionForDependencies, branch: revision), products: constraint.products)
                } else {
                    revisionForDependencies = revision
                    overriddenPackages[package] = (version: .revision(revision), products: constraint.products)
                }
                wave.append((constraint: constraint, revision: revision, revisionForDependencies: revisionForDependencies))
            }

            if wave.isEmpty { continue }

            let perConstraintDeps = try await withThrowingTaskGroup(
                of: (Int, [(DependencyResolutionNode, [Constraint])]).self
            ) { group in
                for (i, item) in wave.enumerated() {
                    let constraint = item.constraint
                    let revision = item.revision
                    let revisionForDependencies = item.revisionForDependencies
                    group.addTask {
                        let container = try await withCheckedThrowingContinuation { continuation in
                            self.provider.getContainer(
                                for: constraint.package,
                                completion: { continuation.resume(with: $0) }
                            )
                        }
                        var nodeDeps: [(DependencyResolutionNode, [Constraint])] = []
                        for node in constraint.nodes() {
                            var unprocessedDependencies = try await container.underlying.getDependencies(
                                at: revisionForDependencies,
                                productFilter: constraint.products,
                                node.enabledTraits
                            )
                            if let sharedRevision = node.revisionLock(revision: revision) {
                                unprocessedDependencies.append(sharedRevision)
                            }
                            nodeDeps.append((node, unprocessedDependencies))
                        }
                        return (i, nodeDeps)
                    }
                }
                var results = [[(DependencyResolutionNode, [Constraint])]](
                    repeating: [],
                    count: wave.count
                )
                for try await (i, deps) in group {
                    results[i] = deps
                }
                return results
            }

            for (i, nodeDepsList) in perConstraintDeps.enumerated() {
                let originalConstraint = wave[i].constraint
                for (_, deps) in nodeDepsList {
                    for dependency in deps {
                        switch dependency.requirement {
                        case .versionSet(let req):
                            for node in dependency.nodes() {
                                let versionedBasedConstraint = VersionBasedConstraint(node: node, req: req)
                                versionBasedDependencies[.root(package: originalConstraint.package), default: []].append(versionedBasedConstraint)
                            }
                        case .revision:
                            constraints.append(dependency)
                        case .unversioned:
                            throw DependencyResolverError.revisionDependencyContainsLocalPackage(
                                dependency: originalConstraint.package.identity.description,
                                localPackage: dependency.package.identity.description
                            )
                        }
                    }
                }
            }
        }

        // At this point, we should be left with only version-based requirements in our constraints
        // list. Add them to our version-based dependency list.
        for constraint in constraints {
            switch constraint.requirement {
            case .versionSet(let req):
                for node in constraint.nodes() {
                    let versionedBasedConstraint = VersionBasedConstraint(node: node, req: req)
                    versionBasedDependencies[root, default: []].append(versionedBasedConstraint)
                }
            case .revision, .unversioned:
                throw InternalError("Unexpected revision/unversioned requirement in the constraints list: \(constraints)")
            }
        }

        // Finally, compute the root incompatibilities (which will be all version-based).
        // note versionBasedDependencies may point to the root package dependencies, or the dependencies of root's non-versioned dependencies
        var rootIncompatibilities: [Incompatibility] = []
        for (node, constraints) in versionBasedDependencies {
            for constraint in constraints {
                if overriddenPackages.keys.contains(constraint.node.package) { continue }
                let incompat = try Incompatibility(
                    Term(root, .exact("1.0.0")),
                    Term(not: constraint.node, constraint.requirement),
                    root: root,
                    cause: .dependency(node: node)
                )
                rootIncompatibilities.append(incompat)
            }
        }

        return (overriddenPackages, rootIncompatibilities)
    }

    /// Perform unit propagation, resolving conflicts if necessary and making
    /// decisions if nothing else is left to be done.
    /// After this method returns `solution` is either populated with a list of
    /// final version assignments or an error is thrown.
    private func run(state: State) async throws {
        var next: DependencyResolutionNode? = state.root

        while let nxt = next {
            try self.propagate(state: state, node: nxt)

            // initiate prefetch of known packages that will be used to make the decision on the next step
            self.provider.prefetch(containers: state.solution.undecided.map(\.node.package))

            // If decision making determines that no more decisions are to be
            // made, it returns nil to signal that version solving is done.
            next = try await self.makeDecision(state: state)
        }
    }

    /// Perform unit propagation to derive new assignments based on the current
    /// partial solution.
    /// If a conflict is found, the conflicting incompatibility is returned to
    /// resolve the conflict on.
    internal func propagate(state: State, node: DependencyResolutionNode) throws {
        var changed: OrderedCollections.OrderedSet<DependencyResolutionNode> = [node]

        while !changed.isEmpty {
            let package = changed.removeFirst()
            loop: for incompatibility in state.positiveIncompatibilities(for: package)?.reversed() ?? [] {
                let result = self.propagate(state: state, incompatibility: incompatibility)

                switch result {
                case .conflict:
                    let rootCause = try self.resolve(state: state, conflict: incompatibility)
                    let rootCauseResult = self.propagate(state: state, incompatibility: rootCause)

                    guard case .almostSatisfied(let pkg) = rootCauseResult else {
                        throw InternalError("""
                        Expected root cause \(rootCause) to almost satisfy the \
                        current partial solution:
                        \(state.solution.assignments.map { " * \($0.description)" }.joined(separator: "\n"))\n
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

    private func propagate(state: State, incompatibility: Incompatibility) -> PropagationResult {
        var unsatisfied: Term?

        for term in incompatibility.terms {
            let relation = state.solution.relation(with: term)

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


        state.derive(unsatisfiedTerm.inverse, cause: incompatibility)
        self.delegate?.derived(term: unsatisfiedTerm.inverse)
        return .almostSatisfied(node: unsatisfiedTerm.node)
    }

    // Based on:
    // https://github.com/dart-lang/pub/tree/master/doc/solver.md#conflict-resolution
    // https://github.com/dart-lang/pub/blob/master/lib/src/solver/version_solver.dart#L201
    internal func resolve(state: State, conflict: Incompatibility) throws -> Incompatibility {
        self.delegate?.conflict(conflict: conflict)

        var incompatibility = conflict
        var createdIncompatibility = false

        // rdar://93335995
        // hard protection from infinite loops
        let maxIterations = 1000
        var iterations = 0

        while !isCompleteFailure(incompatibility, root: state.root) {
            var mostRecentTerm: Term?
            var mostRecentSatisfier: Assignment?
            var difference: Term?
            var previousSatisfierLevel = 0

            for term in incompatibility.terms {
                let satisfier = try state.solution.satisfier(for: term)

                if let _mostRecentSatisfier = mostRecentSatisfier {
                    let mostRecentSatisfierIdx = state.solution.assignments.firstIndex(of: _mostRecentSatisfier)!
                    let satisfierIdx = state.solution.assignments.firstIndex(of: satisfier)!

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
                    if let difference {
                        previousSatisfierLevel = max(previousSatisfierLevel, try state.solution.satisfier(for: difference.inverse).decisionLevel)
                    }
                }
            }

            guard let _mostRecentSatisfier = mostRecentSatisfier else {
                throw InternalError("mostRecentSatisfier not set")
            }

            if previousSatisfierLevel < _mostRecentSatisfier.decisionLevel || _mostRecentSatisfier.cause == nil {
                state.backtrack(toDecisionLevel: previousSatisfierLevel)
                if createdIncompatibility {
                    state.addIncompatibility(incompatibility, at: .conflictResolution)
                }
                return incompatibility
            }

            let priorCause = _mostRecentSatisfier.cause!

            var newTerms = Array(incompatibility.terms.filter { $0 != mostRecentTerm })
            newTerms += priorCause.terms.filter { $0.node != _mostRecentSatisfier.term.node }

            if let _difference = difference {
                // rdar://93335995
                // do not add the exact inverse of a requirement as it can lead to endless loops
                if _difference.inverse != mostRecentTerm {
                    newTerms.append(_difference.inverse)
                }
            }

            incompatibility = try Incompatibility(
                OrderedCollections.OrderedSet(newTerms),
                root: state.root,
                cause: .conflict(cause: .init(conflict: incompatibility, other: priorCause))
            )
            createdIncompatibility = true

            if let mostRecentTerm {
                if let difference {
                    self.delegate?.partiallySatisfied(term: mostRecentTerm, by: _mostRecentSatisfier, incompatibility: incompatibility, difference: difference)
                } else {
                    self.delegate?.satisfied(term: mostRecentTerm, by: _mostRecentSatisfier, incompatibility: incompatibility)
                }
            }

            // rdar://93335995
            // hard protection from infinite loops
            iterations = iterations + 1
            if iterations >= maxIterations {
                break
            }
        }

        self.delegate?.failedToResolve(incompatibility: incompatibility)
        throw PubGrubError._unresolvable(incompatibility, state.incompatibilities)
    }

    /// Does a given incompatibility specify that version solving has entirely
    /// failed, meaning this incompatibility is either empty or only for the root
    /// package.
    private func isCompleteFailure(_ incompatibility: Incompatibility, root: DependencyResolutionNode) -> Bool {
        incompatibility.terms.isEmpty || (incompatibility.terms.count == 1 && incompatibility.terms.first?.node == root)
    }

    private func computeCounts(
        for terms: [Term]
    ) async throws -> [Term: Int] {
        if terms.isEmpty {
            return [:]
        }
        return try await withThrowingTaskGroup(of: (Term, Int).self) { group in
            for term in terms {
                group.addTask {
                    let container = try await withCheckedThrowingContinuation { continuation in
                        self.provider.getContainer(for: term.node.package, completion: {
                            continuation.resume(with: $0)
                        })
                    }
                    return try await (term, container.versionCount(term.requirement))
                }
            }

            return try await group.reduce(into: [:]) { partialResult, termCount in
                partialResult[termCount.0] = termCount.1
            }
        }
    }

    internal func makeDecision(
        state: State
    ) async throws -> DependencyResolutionNode? {
        // If there are no more undecided terms, version solving is complete.
        let undecided = state.solution.undecided
        guard !undecided.isEmpty else {
            return nil
        }

        // Prefer packages with least number of versions that fit the current requirements so we
        // get conflicts (if any) sooner.
        let start = DispatchTime.now()
        let counts = try await self.computeCounts(for: undecided)
        // forced unwraps safe since we are testing for count and errors above
        let pkgTerm = undecided.min {
            // Prefer packages that don't allow pre-release versions
            // to allow propagation logic to find dependencies that
            // limit the range before making any decisions. This means
            // that we'd always prefer release versions.
            if $0.supportsPrereleases != $1.supportsPrereleases {
                return !$0.supportsPrereleases
            }

            return counts[$0]! < counts[$1]!
        }!
        self.delegate?.willResolve(term: pkgTerm)
        // at this point the container is cached
        let container = try self.provider.getCachedContainer(for: pkgTerm.node.package)

        // Get the best available version for this package.
        guard let version = try await container.getBestAvailableVersion(for: pkgTerm) else {
            state.addIncompatibility(try Incompatibility(pkgTerm, root: state.root, cause: .noAvailableVersion), at: .decisionMaking)
            return pkgTerm.node
        }

        // Add all of this version's dependencies as incompatibilities.
        let depIncompatibilities = try await container.incompatibilites(
            at: version,
            node: pkgTerm.node,
            overriddenPackages: state.overriddenPackages,
            root: state.root
        )

        var haveConflict = false
        for incompatibility in depIncompatibilities {
            // Add the incompatibility to our partial solution.
            state.addIncompatibility(incompatibility, at: .decisionMaking)

            // Check if this incompatibility will satisfy the solution.
            haveConflict = haveConflict || incompatibility.terms.allSatisfy {
                // We only need to check if the terms other than this package
                // are satisfied because we _know_ that the terms matching
                // this package will be satisfied if we make this version
                // as a decision.
                $0.node == pkgTerm.node || state.solution.satisfies($0)
            }
        }

        // Decide this version if there was no conflict with its dependencies.
        if !haveConflict {
            self.delegate?.didResolve(term: pkgTerm, version: version, duration: start.distance(to: .now()))
            state.decide(pkgTerm.node, at: version)
        }

        return pkgTerm.node
    }
}

internal enum LogLocation: String {
    case topLevel = "top level"
    case unitPropagation = "unit propagation"
    case decisionMaking = "decision making"
    case conflictResolution = "conflict resolution"
}

public extension PubGrubDependencyResolver {
    enum PubGrubError: Swift.Error, CustomStringConvertible {
        case _unresolvable(Incompatibility, [DependencyResolutionNode: [Incompatibility]])
        case unresolvable(String)

        public var description: String {
            switch self {
            case ._unresolvable(let rootCause, _):
                rootCause.description
            case .unresolvable(let error):
                error
            }
        }

        var rootCause: Incompatibility? {
            switch self {
            case ._unresolvable(let rootCause, _):
                rootCause
            case .unresolvable:
                nil
            }
        }

        var incompatibilities: [DependencyResolutionNode: [Incompatibility]]? {
            switch self {
            case ._unresolvable(_, let incompatibilities):
                incompatibilities
            case .unresolvable:
                nil
            }
        }
    }
}

extension PubGrubDependencyResolver {
    private struct VersionBasedConstraint {
        let node: DependencyResolutionNode
        let requirement: VersionSetSpecifier

        init(node: DependencyResolutionNode, req: VersionSetSpecifier) {
            self.node = node
            self.requirement = req
        }

        internal static func constraints(_ constraint: Constraint) -> [VersionBasedConstraint]? {
            switch constraint.requirement {
            case .versionSet(let req):
                constraint.nodes().map { VersionBasedConstraint(node: $0, req: req) }
            case .revision:
                nil
            case .unversioned:
                nil
            }
        }
    }
}

private enum PropagationResult {
    case conflict
    case almostSatisfied(node: DependencyResolutionNode)
    case none
}

private extension PackageRequirement {
    var isRevision: Bool {
        switch self {
        case .versionSet, .unversioned:
            false
        case .revision:
            true
        }
    }
}
