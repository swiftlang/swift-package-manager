/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Version

public enum DependencyResolverError: Error {
    /// The resolver was unable to find a solution to the input constraints.
    case unsatisfiable

    /// The resolver hit unimplemented functionality (used temporarily for test case coverage).
    //
    // FIXME: Eliminate this.
    case unimplemented
}

/// An abstract definition for a set of versions.
public enum VersionSetSpecifier: Equatable {
    /// The universal set.
    case any

    /// The empty set.
    case empty

    /// A non-empty range of version.
    case range(Range<Version>)

    /// Compute the intersection of two set specifiers.
    public func intersection(_ rhs: VersionSetSpecifier) -> VersionSetSpecifier {
        switch (self, rhs) {
        case (.any, _):
            return rhs
        case (_, .any):
            return self
        case (.empty, _):
            return .empty
        case (_, .empty):
            return .empty
        case (.range(let lhs), .range(let rhs)):
            let start = Swift.max(lhs.lowerBound, rhs.lowerBound)
            let end = Swift.min(lhs.upperBound, rhs.upperBound)
            if start < end {
                return .range(start..<end)
            } else {
                return .empty
            }
        default:
            // FIXME: Compiler should be able to prove this? https://bugs.swift.org/browse/SR-2221
            fatalError("not reachable")
        }
    }

    /// Check if the set contains a version.
    public func contains(_ version: Version) -> Bool {
        switch self {
        case .empty:
            return false
        case .range(let range):
            return range.contains(version)
        case .any:
            return true
        }
    }
}
public func ==(_ lhs: VersionSetSpecifier, _ rhs: VersionSetSpecifier) -> Bool {
    switch (lhs, rhs) {
    case (.any, .any):
        return true
    case (.any, _):
        return false
    case (.empty, .empty):
        return true
    case (.empty, _):
        return false
    case (.range(let lhs), .range(let rhs)):
        return lhs == rhs
    case (.range, _):
        return false
    }
}

/// An identifier which unambiguously references a package container.
///
/// This identifier is used to abstractly refer to another container when
/// encoding dependencies across packages.
public protocol PackageContainerIdentifier: Hashable { }

/// A container of packages.
///
/// This is the top-level unit of package resolution, i.e. the unit at which
/// versions are associated.
///
/// It represents a package container (e.g., a source repository) which can be
/// identified unambiguously and which contains a set of available package
/// versions and the ability to retrieve the dependency constraints for each of
/// those versions.
///
/// We use the "container" terminology here to differentiate between two
/// conceptual notions of what the package is: (1) informally, the repository
/// containing the package, but from which a package cannot be loaded by itself
/// and (2) the repository at a particular version, at which point the package
/// can be loaded and dependencies enumerated.
///
/// This is also designed in such a way to extend naturally to multiple packages
/// being contained within a single repository, should we choose to support that
/// later.
public protocol PackageContainer {
    /// The type of packages contained.
    associatedtype Identifier: PackageContainerIdentifier

    /// The identifier for the package.
    var identifier: Identifier { get }

    /// Get the list of versions which are available for the package.
    ///
    /// The list will be returned in sorted order, with the latest version last.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    //
    // FIXME: It is possible this protocol could one day be more efficient if it
    // returned versions more lazily, e.g., if we could fetch them iteratively
    // from the server. This might mean we wouldn't need to pull down as much
    // content.
    var versions: [Version] { get }

    /// Fetch the declared dependencies for a particular version.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Precondition: `versions.contains(version)`
    /// - Throws: If the version could not be resolved; this will abort
    ///   dependency resolution completely.
    //
    // FIXME: We should perhaps define some particularly useful error codes
    // here, so the resolver can handle errors more meaningfully.
    func getDependencies(at version: Version) throws -> [PackageContainerConstraint<Identifier>]
}

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    associatedtype Container: PackageContainer

    /// Get the container for a particular identifier.
    ///
    /// - Throws: If the package container could not be resolved or loaded.
    func getContainer(for identifier: Container.Identifier) throws -> Container
}

/// An individual constraint onto a container.
public struct PackageContainerConstraint<T: PackageContainerIdentifier> {
    public typealias Identifier = T

    /// The identifier for the container the constraint is on.
    public let identifier: Identifier

    /// The version requirements.
    public let versionRequirement: VersionSetSpecifier

    /// Create a constraint requiring the given `container` satisfying the
    /// `versionRequirement`.
    public init(container identifier: Identifier, versionRequirement: VersionSetSpecifier) {
        self.identifier = identifier
        self.versionRequirement = versionRequirement
    }
}

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
    associatedtype Identifier: PackageContainerIdentifier

    /// Called when a new container is being considered.
    func added(container identifier: Identifier)
}

/// A bound version for a package within an assignment.
//
// FIXME: This should be nested, but cannot be currently.
enum BoundVersion: Equatable {
    /// The assignment should not include the package.
    ///
    /// This is different from the absence of an assignment for a particular
    /// package, which only indicates the assignment is agnostic to its
    /// version. This value signifies the package *may not* be present.
    case excluded

    /// The version of the package to include.
    case version(Version)
}
func ==(_ lhs: BoundVersion, _ rhs: BoundVersion) -> Bool {
    switch (lhs, rhs) {
    case (.excluded, .excluded):
        return true
    case (.excluded, _):
        return false
    case (.version(let lhs), .version(let rhs)):
        return lhs == rhs
    case (.version, _):
        return false
    }
}

/// A container for constraints for a set of packages.
///
/// This data structure is only designed to represent satisfiable constraint
/// sets, it cannot represent sets including containers which have an empty
/// constraint.
//
// FIXME: Maybe each package should just return this, instead of a list of
// `PackageContainerConstraint`s. That won't work if we decide this should
// eventually map based on the `Container` rather than the `Identifier`, though,
// so they are separate for now.
struct PackageContainerConstraintSet<C: PackageContainer>: Collection {
    typealias Container = C
    typealias Identifier = Container.Identifier

    typealias Index = Dictionary<Identifier, VersionSetSpecifier>.Index
    typealias Element = Dictionary<Identifier, VersionSetSpecifier>.Element

    /// The set of constraints.
    private var constraints: [Identifier: VersionSetSpecifier]

    /// Create an empty constraint set.
    init() {
        self.constraints = [:]
    }

    /// Create an constraint set from known values.
    ///
    /// The initial constraints should never be unsatisfiable.
    init(_ constraints: [Identifier: VersionSetSpecifier]) {
        assert(constraints.values.filter({ $0 == .empty }).isEmpty)
        self.constraints = constraints
    }

    /// The list of containers with entries in the set.
    var containerIdentifiers: AnySequence<Identifier> {
        return AnySequence<C.Identifier>(constraints.keys)
    }

    /// Get the version set specifier associated with the given package `identifier`.
    subscript(identifier: Identifier) -> VersionSetSpecifier {
        return constraints[identifier] ?? .any
    }

    /// Create a constraint set by merging the `versionRequirement` for container `identifier`.
    ///
    /// - Returns: The new set, or nil the resulting set is unsatisfiable.
    private func merging(
        versionRequirement: VersionSetSpecifier, for identifier: Identifier
    ) -> PackageContainerConstraintSet<C>?
    {
        let intersection = self[identifier].intersection(versionRequirement)
        if intersection == .empty {
            return nil
        }
        var result = self
        result.constraints[identifier] = intersection
        return result
    }

    /// Create a constraint set by merging `constraint`.
    ///
    /// - Returns: The new set, or nil the resulting set is unsatisfiable.
    func merging(_ constraint: PackageContainerConstraint<Identifier>) -> PackageContainerConstraintSet<C>? {
        return merging(versionRequirement: constraint.versionRequirement, for: constraint.identifier)
    }

    /// Create a new constraint set by merging the given constraint set.
    ///
    /// - Returns: False if the merger has made the set unsatisfiable; i.e. true
    /// when the resulting set is satisfiable, if it was already so.
    func merging(
        _ constraints: PackageContainerConstraintSet<Container>
    ) -> PackageContainerConstraintSet<C>?
    {
        var result = self
        for (key, versionRequirement) in constraints {
            guard let merged = result.merging(versionRequirement: versionRequirement, for: key) else {
                return nil
            }
            result = merged
        }
        return result
    }

    // MARK: Collection Conformance

    var startIndex: Index {
        return constraints.startIndex
    }

    var endIndex: Index {
        return constraints.endIndex
    }

    func index(after i: Index) -> Index {
        return constraints.index(after: i)
    }

    subscript(position: Index) -> Element {
        return constraints[position]
    }
}

/// A container for version assignments for a set of packages, exposed as a
/// sequence of `Container` to `BoundVersion` bindings.
///
/// This is intended to be an efficient data structure for accumulating a set of
/// version assignments along with efficient access to the derived information
/// about the assignment (for example, the unified set of constraints it
/// induces).
///
/// The set itself is designed to only ever contain a consistent set of
/// assignments, i.e. each assignment should satisfy the induced
/// `constraints`, but this invariant is not explicitly enforced.
//
// FIXME: Actually make efficient.
struct VersionAssignmentSet<C: PackageContainer>: Sequence {
    typealias Container = C
    typealias Identifier = Container.Identifier

    /// The assignment records.
    //
    // FIXME: Does it really make sense to key on the identifier here. Should we
    // require referential equality of containers and use that to simplify?
    private var assignments: [Identifier: (container: Container, binding: BoundVersion)]

    /// Create an empty assignment.
    init() {
        assignments = [:]
    }

    /// The assignment for the given `container`.
    subscript(container: Container) -> BoundVersion? {
        get {
            return assignments[container.identifier]?.binding
        }
        set {
            // We disallow deletion.
            let newBinding = newValue!

            // Validate this is a valid assignment.
            assert(isValid(binding: newBinding, for: container))

            assignments[container.identifier] = (container: container, binding: newBinding)
        }
    }

    /// Create a new assignment set by merging in the bindings from `assignment`.
    ///
    /// - Returns: The new assignment, or nil if the merge cannot be made (the
    /// assignments contain incompatible versions).
    func merging(_ assignment: VersionAssignmentSet<Container>) -> VersionAssignmentSet<Container>? {
        // In order to protect the assignment set, we first have to test whether
        // the merged constraint sets are satisfiable.
        //
        // FIXME: This is very inefficient; we should decide whether it is right
        // to handle it here or force the main resolver loop to handle the
        // discovery of this property.
        guard let _ = constraints.merging(assignment.constraints) else {
            return nil
        }

        // The induced constraints are satisfiable, so we *can* union the
        // assignments without breaking our internal invariant on
        // satisfiability.
        var result = self
        for (container, binding) in assignment {
            if let existing = result[container] {
                if existing != binding {
                    return nil
                }
            } else {
                result[container] = binding
            }
        }

        return result
    }

    /// The combined version constraints induced by the assignment.
    ///
    /// This consists of the merged constraints which need to be satisfied on
    /// each package as a result of the versions selected in the assignment.
    ///
    /// The resulting constraint set is guaranteed to be non-empty for each
    /// mapping, assuming the invariants on the set are followed.
    //
    // FIXME: We need to cache this.
    var constraints: PackageContainerConstraintSet<Container> {
        // Collect all of the constraints.
        var result = PackageContainerConstraintSet<Container>()
        for (_, (container: container, binding: binding)) in assignments {
            switch binding {
            case .excluded:
                // If the package is excluded, it doesn't contribute.
                continue

            case .version(let version):
                // If we have a version, add the constraints from that package version.
                //
                // FIXME: We should cache this too, possibly at a layer
                // different than above (like the entry record).
                //
                // FIXME: Error handling, except that we probably shouldn't have
                // needed to refetch the dependencies at this point.
                for constraint in try! container.getDependencies(at: version) {
                    guard let merged = result.merging(constraint) else {
                        preconditionFailure("unsatisfiable constraint set")
                    }
                    result = merged
                }
            }
        }
        return result
    }

    /// Check if the given `binding` for `container` is valid within the assignment.
    //
    // FIXME: This is currently very inefficient.
    func isValid(binding: BoundVersion, for container: Container) -> Bool {
        switch binding {
        case .excluded:
            // A package can be excluded if there are no constraints on the
            // package (it has not been requested by any other package in the
            // assignment).
            return constraints[container.identifier] == .any

        case .version(let version):
            // A version is valid if it is contained in the constraints.
            return constraints[container.identifier].contains(version)
        }
    }

    /// Check if the assignment is valid and complete.
    func checkIfValidAndComplete() -> Bool {
        // Validity should hold trivially, because it is an invariant of the collection.
        for assignment in assignments.values {
            if !isValid(binding: assignment.binding, for: assignment.container) {
                return false
            }
        }

        // Check completeness, by simply looking at all the entries in the induced constraints.
        for identifier in constraints.containerIdentifiers {
            // Verify we have a non-excluded entry for this key.
            switch assignments[identifier]?.binding {
            case .version?:
                continue
            case .excluded?, nil:
                return false
            }
        }

        return true
    }

    // MARK: Sequence Conformance

    // FIXME: This should really be a collection, but that takes significantly
    // more work given our current backing collection.

    typealias Iterator = AnyIterator<(Container, BoundVersion)>

    func makeIterator() -> Iterator {
        var it = assignments.values.makeIterator()
        return AnyIterator{
            if let next = it.next() {
                return (next.container, next.binding)
            } else {
                return nil
            }
        }
    }
}

/// A general purpose package dependency resolver.
///
/// This is a general purpose solver for the problem of:
///
/// Given an input list of constraints, where each constraint identifies a
/// container and version requirements, and, where each container supplies a
/// list of additional constraints ("dependencies") for an individual version,
/// then, choose an assignment of containers to versions such that:
///
/// 1. The assignment is complete: there exists an assignment for each container
/// listed in the union of the input constraint list and the dependency list for
/// every container in the assignment at the assigned version.
///
/// 2. The assignment is correct: the assigned version satisfies each constraint
/// referencing its matching container.
///
/// 3. The assignment is maximal: there is no other assignment satisfying #1 and
/// #2 such that all assigned version are greater than or equal to the versions
/// assigned in the result.
///
/// NOTE: It does not follow from #3 that this solver attempts to give an
/// "optimal" result. There may be many possible solutions satisfying #1, #2,
/// and #3, and optimality requires additional information (e.g. a
/// prioritization among packages).
///
/// As described, this problem is NP-complete (*). However, this solver does
/// *not* currently attempt to solve the full NP-complete problem, rather it
/// proceeds by first always attempting to choose the latest version of each
/// container under consideration. However, if this version is unavailable due
/// to the current choice of assignments, it will be rejected and no longer
/// considered.
///
/// This algorithm is sound (a valid solution satisfies the assignment
/// guarantees above), but *incomplete*; it may fail to find a valid solution to
/// a satisfiable input.
///
/// (*) Via reduction from 3-SAT: Introduce a package for each variable, with
/// two versions representing true and false. For each clause `C_n`, introduce a
/// package `P(C_n)` representing the clause, with three versions; one for each
/// satisfying assignment of values to a literal with the corresponding precise
/// constraint on the input packages. Finally, construct an input constraint
/// list including a dependency on each clause package `P(C_n)` and an
/// open-ended version constraint. The given input is satisfiable iff the input
/// 3-SAT instance is.
public class DependencyResolver<
    P: PackageContainerProvider,
    D: DependencyResolverDelegate
> where P.Container.Identifier == D.Identifier
{
    public typealias Provider = P
    public typealias Delegate = D
    public typealias Container = Provider.Container
    public typealias Identifier = Container.Identifier

    /// The type of the constraints the resolver operates on.
    ///
    /// Technically this is a container constraint, but that is currently the
    /// only kind of constraints we operate on.
    public typealias Constraint = PackageContainerConstraint<Identifier>

    /// The type of constraint set  the resolver operates on.
    typealias ConstraintSet = PackageContainerConstraintSet<Container>

    /// The type of assignment the resolver operates on.
    typealias AssignmentSet = VersionAssignmentSet<Container>

    /// The container provider used to load package containers.
    public let provider: Provider

    /// The resolver's delegate.
    public let delegate: Delegate

    public init(_ provider: Provider, _ delegate: Delegate) {
        self.provider = provider
        self.delegate = delegate
    }

    /// Execute the resolution algorithm to find a valid assignment of versions.
    ///
    /// - Parameters:
    ///   - constraints: The contraints to solve. It is legal to supply multiple
    ///                  constraints for the same container identifier.
    /// - Returns: A satisfying assignment of containers and versions.
    /// - Throws: DependencyResolverError, or errors from the underlying package provider.
    public func resolve(constraints: [Constraint]) throws -> [(container: Identifier, version: Version)] {
        // Create an assignment for the input constraints.
        guard let assignment = try merge(
                constraints: constraints, into: AssignmentSet(),
                subjectTo: ConstraintSet(), excluding: [:]) else {
            throw DependencyResolverError.unsatisfiable
        }

        return assignment.map { (container, binding) in
            guard case .version(let version) = binding else {
                fatalError("unexpected exclude binding")
            }
            return (container: container.identifier, version: version)
        }
    }

    /// Resolve an individual container dependency tree.
    ///
    /// This is the primary method in our bottom-up algorithm for resolving
    /// dependencies. The inputs define an active set of constraints and set of
    /// versions to exclude (conceptually the latter could be merged with the
    /// former, but it is convenient to separate them in our
    /// implementation). The result is an assignment for this container's
    /// subtree.
    ///
    /// - Parameters:
    ///   - container: The container to resolve.
    ///   - constraints: The external constraints which must be honored by the solution.
    ///   - exclusions: The list of individually excluded package versions.
    /// - Returns: A sequence of feasible solutions, starting with the most preferable.
    /// - Throws: Only rethrows errors from the container provider.
    //
    // FIXME: This needs to a way to return information on the failure, or we
    // will need to have it call the delegate directly.
    //
    // FIXME: @testable private
    func resolveSubtree(
        _ container: Container,
        subjectTo allConstraints: ConstraintSet,
        excluding allExclusions: [Identifier: Set<Version>]
    ) throws -> AssignmentSet? {
        func validVersions(_ container: Container) -> AnyIterator<Version> {
            let constraints = allConstraints[container.identifier]
            let exclusions = allExclusions[container.identifier] ?? Set()
            var it = container.versions.reversed().makeIterator()
            return AnyIterator { () -> Version? in
                    while let version = it.next() {
                        if constraints.contains(version) && !exclusions.contains(version) {
                            return version
                    }
                }
                return nil
            }
        }

        // Attempt to select each valid version in order.
        //
        // FIXME: We must detect recursion here.
        for version in validVersions(container) {
            // Create an assignment for this container and version.
            var assignment = AssignmentSet()
            assignment[container] = .version(version)

            // Get the constraints for this container version and update the
            // assignment to include each one.
            if let result = try merge(
                     constraints: try container.getDependencies(at: version),
                     into: assignment, subjectTo: allConstraints, excluding: allExclusions) {
                // We found a complete valid assignment.
                assert(result.checkIfValidAndComplete())
                return result
            }
        }

        // We were unable to find a valid solution.
        return nil
    }

    /// Solve the `constraints` and merge the results into the `assignment`.
    ///
    /// - Parameters:
    ///   - constraints: The input list of constraints to solve.
    ///   - assignment: The assignment to merge the result into.
    ///   - allConstraints: An additional set of constraints on the viable solutions.
    ///   - allExclusions: A set of package assignments to exclude from consideration.
    /// - Returns: A satisfying assignment, if solvable.
    private func merge(
        constraints: [Constraint],
        into assignment: AssignmentSet,
        subjectTo allConstraints: ConstraintSet,
        excluding allExclusions: [Identifier: Set<Version>]
    ) throws -> AssignmentSet? {
        var assignment = assignment
        var allConstraints = allConstraints

        // Update the active constraint set to include all active constraints.
        //
        // We want to put all of these constraints in up front so that we are
        // more likely to get back a viable solution.
        //
        // FIXME: We should have a test for this, probably by adding some kind
        // of statistics on the number of backtracks.
        for constraint in constraints {
            guard let merged = allConstraints.merging(constraint) else {
                return nil
            }
            allConstraints = merged
        }

        for constraint in constraints {
            // Get the container.
            //
            // Failures here will immediately abort the solution, although in
            // theory one could imagine attempting to find a solution not
            // requiring this container. It isn't clear that is something we
            // would ever want to handle at this level.
            //
            // FIXME: We want to ask for all of these containers up-front to
            // allow for async cloning.
            let container = try getContainer(for: constraint.identifier)

            // Solve for an assignment with the current constraints.
            guard let subtreeAssignment = try resolveSubtree(
                    container, subjectTo: allConstraints, excluding: allExclusions) else {
                // If we couldn't find an assignment, we need to backtrack in some way.
                throw DependencyResolverError.unimplemented
            }

            // We found a valid subtree assignment, attempt to merge it with the
            // current solution.
            guard let newAssignment = assignment.merging(subtreeAssignment) else {
                // The assignment couldn't be merged with the current
                // assignment, or the constraint sets couldn't be merged.
                //
                // This happens when (a) the subtree has a package overlapping
                // with a previous subtree assignment, and (b) the subtrees
                // needed to resolve different versions due to constraints not
                // present in the top-down constraint set.
                throw DependencyResolverError.unimplemented
            }

            // Update the working assignment and constraint set.
            //
            // This should always be feasible, because all prior constraints
            // were part of the input constraint request (see comment around
            // initial `merge` outside the loop).
            assignment = newAssignment
            guard let merged = allConstraints.merging(subtreeAssignment.constraints) else {
                preconditionFailure("unsatisfiable constraints while merging subtree")
            }
            allConstraints = merged
        }

        return assignment
    }

    // MARK: Container Management

    /// The active set of managed containers.
    private var containers: [Identifier: Container] = [:]

    /// Get the container for the given identifier, loading it if necessary.
    private func getContainer(for identifier: Identifier) throws -> Container {
        // Return the cached container, if available.
        if let container = containers[identifier] {
            return container
        }

        // Otherwise, load it.
        return try addContainer(for: identifier)
    }

    /// Add a managed container.
    //
    // FIXME: In order to support concurrent fetching of dependencies, we need
    // to have some measure of asynchronicity here.
    private func addContainer(for identifier: Identifier) throws -> Container {
        assert(!containers.keys.contains(identifier))

        let container = try provider.getContainer(for: identifier)
        containers[identifier] = container

        // Validate the versions in the container.
        let versions = container.versions
        assert(versions.sorted() == versions, "container versions are improperly ordered")

        // Inform the delegate we are considering a new container.
        delegate.added(container: identifier)

        return container
    }
}
