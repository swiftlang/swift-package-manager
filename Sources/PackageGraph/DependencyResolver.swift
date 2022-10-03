//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageModel
import TSCBasic

public protocol DependencyResolver {
    typealias Binding = (package: PackageReference, binding: BoundVersion, products: ProductFilter)
    typealias Delegate = DependencyResolverDelegate
}

public enum DependencyResolverError: Error, Equatable {
     /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: String, localPackage: String)
}

extension DependencyResolverError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        }
    }
}

public protocol DependencyResolverDelegate {
    func willResolve(term: Term)
    func didResolve(term: Term, version: Version, duration: DispatchTimeInterval)

    func derived(term: Term)
    func conflict(conflict: Incompatibility)
    func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility)
    func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term)
    func failedToResolve(incompatibility: Incompatibility)
    func solved(result: [DependencyResolver.Binding])
}

@available(*, deprecated, message: "user verbosity flags instead")
public struct TracingDependencyResolverDelegate: DependencyResolverDelegate {
    private let stream: OutputByteStream

    public init (path: AbsolutePath) throws {
        self.stream = try LocalFileOutputByteStream(path, closeOnDeinit: true, buffered: false)
    }

    public init (stream: OutputByteStream) {
        self.stream = stream
    }

    public func willResolve(term: Term) {
        self.log("resolving: \(term.node.package.identity)")
    }

    public func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        self.log("resolved: \(term.node.package.identity) @ \(version)")
    }

    public func derived(term: Term) {
        self.log("derived: \(term.node.package.identity)")
    }

    public func conflict(conflict: Incompatibility) {
        self.log("conflict: \(conflict)")
    }

    public func failedToResolve(incompatibility: Incompatibility) {
        self.log("failed to resolve: \(incompatibility)")
    }

    public func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {
        log("CR: \(term) is satisfied by \(assignment)")
        log("CR: which is caused by \(assignment.cause?.description ?? "")")
        log("CR: new incompatibility \(incompatibility)")
    }

    public func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {
        log("CR: \(term) is partially satisfied by \(assignment)")
        log("CR: which is caused by \(assignment.cause?.description ?? "")")
        log("CR: new incompatibility \(incompatibility)")
    }

    public func solved(result: [DependencyResolver.Binding]) {
        self.log("solved:")
        for (package, binding, _) in result {
            self.log("\(package) \(binding)")
        }
    }

    private func log(_ message: String) {
        self.stream <<< message <<< "\n"
        self.stream.flush()
    }
}

public struct ObservabilityDependencyResolverDelegate: DependencyResolverDelegate {
    private let observabilityScope: ObservabilityScope

    public init (observabilityScope: ObservabilityScope) {
        self.observabilityScope = observabilityScope.makeChildScope(description: "DependencyResolver")
    }

    public func willResolve(term: Term) {
        self.debug("resolving '\(term.node.package.identity)'")
    }

    public func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        self.debug("resolved '\(term.node.package.identity)' @ '\(version)'")
    }

    public func derived(term: Term) {
        self.debug("derived '\(term.node.package.identity)' requirement '\(term.requirement)'")
    }

    public func conflict(conflict: Incompatibility) {
        self.debug("conflict: \(conflict)")
    }

    public func failedToResolve(incompatibility: Incompatibility) {
        self.debug("failed to resolve '\(incompatibility)'")
    }

    public func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {
        self.debug("'\(term)' is satisfied by '\(assignment)', which is caused by '\(assignment.cause?.description ?? "unknown cause")'. new incompatibility: '\(incompatibility)'")
    }

    public func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {
        self.debug("\(term) is partially satisfied by '\(assignment)', which is caused by '\(assignment.cause?.description ?? "unknown cause")'. new incompatibility \(incompatibility)")
    }

    public func solved(result: [DependencyResolver.Binding]) {
        for (package, binding, _) in result {
            self.debug("solved '\(package.identity)' (\(package.locationString)) at '\(binding)'")
        }
        self.debug("dependency resolution complete!")
    }

    private func debug(_ message: String) {
        self.observabilityScope.emit(debug: "[DependencyResolver] \(message)")
    }
}

public struct MultiplexResolverDelegate: DependencyResolverDelegate {
    private let underlying: [DependencyResolverDelegate]

    public init (_ underlying: [DependencyResolverDelegate]) {
        self.underlying = underlying
    }

    public func willResolve(term: Term) {
        underlying.forEach { $0.willResolve(term: term)  }
    }

    public func didResolve(term: Term, version: Version, duration: DispatchTimeInterval) {
        underlying.forEach { $0.didResolve(term: term, version: version, duration: duration)  }
    }

    public func derived(term: Term) {
        underlying.forEach { $0.derived(term: term)  }
    }

    public func conflict(conflict: Incompatibility) {
        underlying.forEach { $0.conflict(conflict: conflict)  }
    }

    public func satisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility) {
        underlying.forEach { $0.satisfied(term: term, by: assignment, incompatibility: incompatibility)  }
    }

    public func partiallySatisfied(term: Term, by assignment: Assignment, incompatibility: Incompatibility, difference: Term) {
        underlying.forEach { $0.partiallySatisfied(term: term, by: assignment, incompatibility: incompatibility, difference: difference)  }
    }

    public func failedToResolve(incompatibility: Incompatibility) {
        underlying.forEach { $0.failedToResolve(incompatibility: incompatibility)  }
    }

    public func solved(result: [(package: PackageReference, binding: BoundVersion, products: ProductFilter)]) {
        underlying.forEach { $0.solved(result: result)  }
    }

}
