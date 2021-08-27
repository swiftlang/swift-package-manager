/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageGraph
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

/// An individual managed dependency.
///
/// Each dependency will have a checkout containing the sources at a
/// particular revision, and may have an associated version.
public class ManagedDependency {
    /// Represents the state of the managed dependency.
    public enum State: Equatable {
        
        /// The dependency is a managed checkout.
        case checkout(CheckoutState)
        
        /// The dependency is in edited state.
        ///
        /// If the path is non-nil, the dependency is managed by a user and is
        /// located at the path. In other words, this dependency is being used
        /// for top of the tree style development.
        case edited(AbsolutePath?)
        
        // The dependency is a local package.
        case local
        
        /// Returns true if state is checkout.
        var isCheckout: Bool {
            if case .checkout = self { return true }
            return false
        }
    }
    
    /// The package reference.
    public let packageRef: PackageReference
    
    /// The state of the managed dependency.
    public let state: State
    
    /// Returns true if the dependency is edited.
    public var isEdited: Bool {
        switch state {
        case .checkout, .local:
            return false
        case .edited:
            return true
        }
    }
    
    public var checkoutState: CheckoutState? {
        if case .checkout(let checkoutState) = state {
            return checkoutState
        }
        return nil
    }
    
    /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
    public let subpath: RelativePath
    
    /// A dependency which in editable state is based on a dependency from
    /// which it edited from.
    ///
    /// This information is useful so it can be restored when users
    /// unedit a package.
    public internal(set) var basedOn: ManagedDependency?
    
    public var packageIdentity: PackageIdentity {
        self.packageRef.identity
    }
    
    public init(
        packageRef: PackageReference,
        subpath: RelativePath,
        checkoutState: CheckoutState
    ) {
        self.packageRef = packageRef
        self.state = .checkout(checkoutState)
        self.basedOn = nil
        self.subpath = subpath
    }
    
    /// Create a dependency present locally on the filesystem.
    public static func local(
        packageRef: PackageReference
    ) -> ManagedDependency {
        return ManagedDependency(
            packageRef: packageRef,
            state: .local,
            // FIXME: This is just a fake entry, we should fix it.
            subpath: RelativePath(packageRef.identity.description),
            basedOn: nil
        )
    }
    
    internal init(
        packageRef: PackageReference,
        state: State,
        subpath: RelativePath,
        basedOn: ManagedDependency?
    ) {
        self.packageRef = packageRef
        self.subpath = subpath
        self.basedOn = basedOn
        self.state = state
    }
    
    private init(
        basedOn dependency: ManagedDependency,
        subpath: RelativePath,
        unmanagedPath: AbsolutePath?
    ) {
        assert(dependency.state.isCheckout)
        self.basedOn = dependency
        self.packageRef = dependency.packageRef
        self.subpath = subpath
        self.state = .edited(unmanagedPath)
    }
    
    /// Create an editable managed dependency based on a dependency which
    /// was *not* in edit state.
    ///
    /// - Parameters:
    ///     - subpath: The subpath inside the editable directory.
    ///     - unmanagedPath: A custom absolute path instead of the subpath.
    public func editedDependency(subpath: RelativePath, unmanagedPath: AbsolutePath?) -> ManagedDependency {
        return ManagedDependency(basedOn: self, subpath: subpath, unmanagedPath: unmanagedPath)
    }
}

extension ManagedDependency: CustomStringConvertible {
    public var description: String {
        return "<ManagedDependency: \(self.packageRef.name) \(self.state)>"
    }
}


// MARK: - ManagedDependencies

/// A collection of managed dependencies.
public final class ManagedDependencies {
    /// The dependencies keyed by the package URL.
    internal var dependencyMap: [String: ManagedDependency]
    
    init(dependencyMap: [String: ManagedDependency] = [:]) {
        self.dependencyMap = dependencyMap
    }
    
    public subscript(forURL url: String) -> ManagedDependency? {
        dependencyMap[url]
    }
    
    public subscript(forIdentity identity: PackageIdentity) -> ManagedDependency? {
        dependencyMap.values.first(where: { $0.packageRef.identity == identity })
    }
    
    public subscript(forNameOrIdentity nameOrIdentity: String) -> ManagedDependency? {
        let lowercasedNameOrIdentity = nameOrIdentity.lowercased()
        return dependencyMap.values.first(where: {
            $0.packageRef.name == nameOrIdentity || $0.packageRef.identity.description == lowercasedNameOrIdentity
        })
    }
    
    public func add(_ dependency: ManagedDependency) {
        self.dependencyMap[dependency.packageRef.location] = dependency
    }
    
    public func remove(forURL url: String) {
        self.dependencyMap[url] = nil
    }
}

extension ManagedDependencies: Collection {
    public typealias Index = Dictionary<String, ManagedDependency>.Index
    public typealias Element = ManagedDependency
    
    public var startIndex: Index {
        self.dependencyMap.startIndex
    }
    
    public var endIndex: Index {
        self.dependencyMap.endIndex
    }
    
    public subscript(index: Index) -> Element {
        self.dependencyMap[index].value
    }
    
    public func index(after index: Index) -> Index {
        self.dependencyMap.index(after: index)
    }
}

extension ManagedDependencies: CustomStringConvertible {
    public var description: String {
        "<ManagedDependencies: \(Array(dependencyMap.values))>"
    }
}
