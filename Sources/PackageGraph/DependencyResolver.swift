/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

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
    func didResolve(term: Term, version: Version)

    func derived(term: Term)
    func conflict(conflict: Incompatibility)
    func satisfied(term: Term, by: Assignment, incompatibility: Incompatibility)
    func partiallySatisfied(term: Term, by: Assignment, incompatibility: Incompatibility, difference: Term)
    func failedToResolve(incompatibility: Incompatibility)
    func computed(bindings: [DependencyResolver.Binding])
}

public struct TracingDependencyResolverDelegate: DependencyResolverDelegate {
    private let stream: OutputByteStream

    public init (path: AbsolutePath) throws {
        self.stream = try LocalFileOutputByteStream(path, closeOnDeinit: true, buffered: false)
    }

    public init (stream: OutputByteStream) {
        self.stream = stream
    }

    public func willResolve(term: Term) {
        self.log("resolving: \(term.node.package.location)")
    }

    public func didResolve(term: Term, version: Version) {
        self.log("resolved: \(term.node.package.location) @ \(version)")
    }

    public func derived(term: Term) {
        self.log("derived: \(term.node.package.location)")
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

    public func computed(bindings: [DependencyResolver.Binding]) {
        self.log("solved:")
        for (container, binding, _) in bindings {
            self.log("\(container) \(binding)")
        }
    }

    private func log(_ message: String) {
        self.stream <<< message <<< "\n"
        self.stream.flush()
    }
}
