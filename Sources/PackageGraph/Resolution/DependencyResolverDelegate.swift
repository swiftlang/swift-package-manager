//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageModel

import struct TSCUtility.Version

package protocol DependencyResolverDelegate {
    func willResolve(term: Term)
    func didResolve(term: Term, version: Version, duration: DispatchTimeInterval)

    func derived(term: Term)
    func conflict(conflict: Incompatibility)
    func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility)
    func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term)
    func failedToResolve(incompatibility: Incompatibility)
    func solved(result: [DependencyResolverBinding])
}

package struct ObservabilityDependencyResolverDelegate: DependencyResolverDelegate {
    private let observabilityScope: ObservabilityScope

    package init (observabilityScope: ObservabilityScope) {
        self.observabilityScope = observabilityScope.makeChildScope(description: "DependencyResolver")
    }

    package func willResolve(term: Term) {
        self.debug("resolving '\(term.node.package.identity)'")
    }

    package func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        self.debug("resolved '\(term.node.package.identity)' @ '\(version)'")
    }

    package func derived(term: Term) {
        self.debug("derived '\(term.node.package.identity)' requirement '\(term.requirement)'")
    }

    package func conflict(conflict: Incompatibility) {
        self.debug("conflict: \(conflict)")
    }

    package func failedToResolve(incompatibility: Incompatibility) {
        self.debug("failed to resolve '\(incompatibility)'")
    }

    package func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {
        self.debug("'\(term)' is satisfied by '\(assignment)', which is caused by '\(assignment.cause?.description ?? "unknown cause")'. new incompatibility: '\(incompatibility)'")
    }

    package func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {
        self.debug("\(term) is partially satisfied by '\(assignment)', which is caused by '\(assignment.cause?.description ?? "unknown cause")'. new incompatibility \(incompatibility)")
    }

    package func solved(result: [DependencyResolverBinding]) {
        for binding in result {
            self.debug("solved '\(binding.package.identity)' (\(binding.package.locationString)) at '\(binding.boundVersion)'")
        }
        self.debug("dependency resolution complete!")
    }

    private func debug(_ message: String) {
        self.observabilityScope.emit(debug: "[DependencyResolver] \(message)")
    }
}

public struct MultiplexResolverDelegate: DependencyResolverDelegate {
    private let underlying: [DependencyResolverDelegate]

    package init (_ underlying: [DependencyResolverDelegate]) {
        self.underlying = underlying
    }

    package func willResolve(term: Term) {
        underlying.forEach { $0.willResolve(term: term)  }
    }

    package func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        underlying.forEach { $0.didResolve(term: term, version: version, duration: duration)  }
    }

    package func derived(term: Term) {
        underlying.forEach { $0.derived(term: term)  }
    }

    package func conflict(conflict: Incompatibility) {
        underlying.forEach { $0.conflict(conflict: conflict)  }
    }

    package func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {
        underlying.forEach { $0.satisfied(term: term, by: assignment, incompatibility: incompatibility)  }
    }

    package func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {
        underlying.forEach { $0.partiallySatisfied(term: term, by: assignment, incompatibility: incompatibility, difference: difference)  }
    }

    package func failedToResolve(incompatibility: Incompatibility) {
        underlying.forEach { $0.failedToResolve(incompatibility: incompatibility)  }
    }

    package func solved(result: [DependencyResolverBinding]) {
        underlying.forEach { $0.solved(result: result)  }
    }

}
