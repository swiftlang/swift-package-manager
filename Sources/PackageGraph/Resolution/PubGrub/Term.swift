//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

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
        Term(
            node: self.node,
            requirement: self.requirement,
            isPositive: !self.isPositive
        )
    }

    package var supportsPrereleases: Bool {
        self.requirement.supportsPrereleases
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
        return self.intersect(withRequirement: other.requirement, andPolarity: other.isPositive)
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

        return Term(node: self.node, requirement: versionIntersection, isPositive: isPositive)
    }

    public func difference(with other: Term) -> Term? {
        self.intersect(with: other.inverse)
    }

    /// Verify if the term fulfills all requirements to be a valid choice for
    /// making a decision in the given partial solution.
    /// - There has to exist a positive derivation for it.
    /// - There has to be no decision for it.
    /// - The package version has to match all assignments.
    public func isValidDecision(for solution: PartialSolution) -> Bool {
        // The intersection between release and pre-release ranges is
        // allowed to produce a pre-release range. This means that the
        // solver is allowed to make a pre-release version decision
        // even when some of the versions didn't allow pre-releases.
        //
        // This means that we should ignore pre-release differences
        // while checking derivations and assert only if the term is
        // pre-release but the last assignment wasn't.
        if self.supportsPrereleases {
            if let assignment = solution.assignments.last(where: { $0.term.node == self.node }) {
                assert(assignment.term.supportsPrereleases)
            }
        }

        for assignment in solution.assignments where assignment.term.node == self.node {
            assert(!assignment.isDecision, "Expected assignment to be a derivation.")

            // This is not great but dragging `ignorePrereleases` through all the APIs seems
            // worse. This is valid because we can have a derivation chain which is something
            // like - "0.0.1"..<"1.0.0" -> "0.0.4-latest"..<"0.0.6" and make a decision
            // `0.0.4-alpha5` based on that if there is no `0.0.4` release. In vacuum this is
            // (currently) incorrect because `0.0.4-alpha5` doesn't satisfy the initial
            // range that doesn't support pre-release versions. Since the solver is
            // allowed to derive a pre-release range we consider the original range to
            // be pre-release range implicitly.
            let term = if self.supportsPrereleases && !assignment.term.supportsPrereleases {
                Term(self.node, self.requirement.withoutPrereleases)
            } else {
                self
            }

            guard term.satisfies(assignment.term) else { return false }
        }
        return true
    }

    // From: https://github.com/dart-lang/pub/blob/master/lib/src/solver/term.dart
    public func relation(with other: Term) -> SetRelation {
        if self.node != other.node {
            assertionFailure("attempting to compute relation between different packages \(self) \(other)")
            return .error
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
        // for error condition
        case error
    }
}

extension Term: CustomStringConvertible {
    public var description: String {
        let pkg = "\(node)"
        let req = self.requirement.description

        if !self.isPositive {
            return "¬\(pkg) \(req)"
        }
        return "\(pkg) \(req)"
    }
}

extension VersionSetSpecifier {
    fileprivate func containsAll(_ other: VersionSetSpecifier) -> Bool {
        self.intersection(other) == other
    }

    fileprivate func containsAny(_ other: VersionSetSpecifier) -> Bool {
        self.intersection(other) != .empty
    }
}
