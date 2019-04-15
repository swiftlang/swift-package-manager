/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 -----------------------------------------------------------------------------
 
 Simple types for sorting targets (both package targets and Xcode targets).
 This is useful for sorting the groups or targets within an Xcode project
 according to criteria such as manifest declaration order, accounting for
 dependent packages as well.
 
 When the pbxproj is generated, the package targets are received from the
 package graph unordered due to the implementation of PackageGraph.
 This API uses the concept of a sort descriptor to order targets in the following order,
 and does so generically to avoid duplicate logic between resolved package targets and
 Xcode targets.
 
 1. Root Package Description
 2. Root Aggregate Products
 3. Root Targets
 4. Root Test Targets
 5. Dependency 1 Package Description
 6. Dependency 1 Aggregate Products
 7. Dependency 1 Targets
 8. Dependency 1 Test Targets
 9. (Repeated for dependencies in alhabetical order)
 
 When sorting in this order, the sort descriptor stores a context with various dictionaries
 to ensure sorting can still take place in O(n) time (in the case of no collisions).
 
 These procedures are preferable to sorting the targets in the graph upstream because manifest order
 sorting should be contained to the Xcodeproj module as long as it is the only client needing
 this behavior.
 */

import PackageGraph
import PackageModel

/// Conforming types may be sorted according to the rules for sorting targets
/// in an Xcode project.
protocol TargetSortable {
    /// The name of the target.
    var name: String { get }
    /// The underlying Swift PM object that this target represents.
    var underlyingArtifact: Xcode.Target.UnderlyingArtifact? { get }
}

// Resolved targets are their own underlying object.
extension ResolvedTarget: TargetSortable {
    
    var underlyingArtifact: Xcode.Target.UnderlyingArtifact? {
        return .target(self)
    }
    
}

extension Xcode.Target: TargetSortable {}

extension Xcode.Target.UnderlyingArtifact {
    
    /// The Swift package this Xcode target was generated from.
    ///
    /// - Parameter context: A sort context with object maps.
    /// - Returns: The package this Xcode target was generated from, if one can be determined.
    fileprivate func package(lookingIn context: TargetSortDescriptor.Context) -> ResolvedPackage? {
        switch self {
        case .packageDescription(let package):
            return package
        case .target(let target):
            return context.packagesByTarget[target]
        case .product(let product):
            return context.packagesByProduct[product]
        }
    }
    
    /// Whether this artifact is a Swift package and the target is therefore a package description target.
    fileprivate var isPackageDescription: Bool {
        if case .packageDescription = self {
            return true
        }
        return false
    }
    
    /// Whether this artifact is a Swift product.
    fileprivate var isProduct: Bool {
        if case .product = self {
            return true
        }
        return false
    }
    
    /// Whether this artifact is a test product or target.
    fileprivate var isTest: Bool {
        switch self {
        case .packageDescription:
            return false
        case .target(let target):
            return target.type == .test
        case .product(let product):
            return product.type == .test
        }
    }
    
}

/// A sort descriptor for sorting targets.
enum TargetSortDescriptor {
    /// Sort targets alphabetically by name.
    case alphabetical
    /// Sort targets by the declaration order in the manifest.
    case declarationOrder(Context)
    
    /// Creates a new declaration-order sort descriptor using the given mappings.
    ///
    /// - Parameters:
    ///   - graph: The fully-resolved package graph.
    ///   - packagesByTarget: A mapping of targets to the package they belong to.
    ///   - packagesByProduct: A mapping of products to the package they belong to.
    ///   - manifestOrderByPackageAndName: A mapping of manifest order indices keyed by package then product/target name.
    /// - Returns: A declaration-order target sort descriptor.
    static func declarationOrder(graph: PackageGraph,
                                 packagesByTarget: [ResolvedTarget: ResolvedPackage],
                                 packagesByProduct: [ResolvedProduct: ResolvedPackage],
                                 manifestOrderByPackageAndName: [ResolvedPackage: [String: Int]]) -> TargetSortDescriptor {
        return declarationOrder(Context(graph: graph,
                                        packagesByTarget: packagesByTarget,
                                        packagesByProduct: packagesByProduct,
                                        manifestOrderByPackageAndName: manifestOrderByPackageAndName))
    }
    
    /// A context of mappings necessary for sorting targets by declaration order.
    struct Context {
        
        /// The fully-resolved package graph.
        fileprivate let packageGraph: PackageGraph
        
        /// A mapping of targets to the package they belong to.
        fileprivate let packagesByTarget: [ResolvedTarget: ResolvedPackage]
        
        /// A mapping of products to the package they belong to.
        fileprivate let packagesByProduct: [ResolvedProduct: ResolvedPackage]
        
        /// A mapping of manifest order indices keyed by package then product/target name.
        fileprivate let manifestOrderByPackageAndName: [ResolvedPackage: [String: Int]]
        
        /// Creates a new context for declaration-order target sorting.
        ///
        /// - Parameters:
        ///   - graph: The fully-resolved package graph.
        ///   - packagesByTarget: A mapping of targets to the package they belong to.
        ///   - packagesByProduct: A mapping of products to the package they belong to.
        ///   - manifestOrderByPackageAndName: A mapping of manifest order indices keyed by package then product/target name.
        init(graph: PackageGraph,
             packagesByTarget: [ResolvedTarget: ResolvedPackage],
             packagesByProduct: [ResolvedProduct: ResolvedPackage],
             manifestOrderByPackageAndName: [ResolvedPackage: [String: Int]]) {
            self.packageGraph = graph
            self.packagesByTarget = packagesByTarget
            self.packagesByProduct = packagesByProduct
            self.manifestOrderByPackageAndName = manifestOrderByPackageAndName
        }
    }
    
    /// Returns `true` iff `item1` and `item2` are already in increasing order.
    ///
    /// - Parameters:
    ///   - target1: The first target.
    ///   - target2: The second target.
    /// - Returns: `true` iff `item1` and `item2` are already in increasing order.
    fileprivate func areInIncreasingOrder<T: TargetSortable>(_ target1: T, _ target2: T) -> Bool {
        switch self {
        case .alphabetical:
            return target1.name < target2.name
        case .declarationOrder(let context):
            return areInIncreasingOrder(target1, target2, context: context)
        }
    }
    
    /// Returns `true` iff `item1` and `item2` are already in increasing order according to the manifest.
    ///
    /// - Parameters:
    ///   - item1: The first item.
    ///   - item2: The second item.
    ///   - context: A sorting context for declaration order.
    /// - Returns: `true` iff `item1` and `item2` are already in increasing order.
    private func areInIncreasingOrder<T: TargetSortable>(_ item1: T, _ item2: T, context: Context) -> Bool {
        guard let item1Artifact = item1.underlyingArtifact,
            let item2Artifact = item2.underlyingArtifact else {
            // We can't sort reliably without both types. Fallback to alphabetical.
            return item1.name < item2.name
        }
        
        guard let package1 = item1Artifact.package(lookingIn: context),
            let package2 = item2Artifact.package(lookingIn: context) else {
                // Couldn't find packages for target. This really shouldn't happen.
                assertionFailure("Unexpected item not in package.")
                // Fall back to alphabetical.
                return item1.name < item2.name
        }
        
        let item1IsRoot = context.packageGraph.rootPackages.contains(package1)
        let item2IsRoot = context.packageGraph.rootPackages.contains(package2)
        
        // Package description targets should always come last.
        // If this is not the case, `xcodebuild -alltargets` does not properly build any targets
        // listed after the package description target.
        if item1Artifact.isPackageDescription != item2Artifact.isPackageDescription {
            return item2Artifact.isPackageDescription
        }
        
        // Root items should be ordered before dependency items.
        if item1IsRoot != item2IsRoot {
            // One item is root and one isn't. The root item should come first.
            return item1IsRoot
        }
        
        // If both items are dependencies from different packages, order alphabetically by package name.
        if !item1IsRoot && package1 != package2 {
            return package1.name < package2.name
        }
        
        // If we got this far, neither one should be a package description target.
        assert(!item1Artifact.isPackageDescription && !item2Artifact.isPackageDescription)
        
        // Product (aggregate) targets should come before regular targets.
        if item1Artifact.isProduct != item2Artifact.isProduct {
            return item1Artifact.isProduct
        }
        
        // Test targets/products should come after others (within their package).
        if item1Artifact.isTest != item2Artifact.isTest {
            // One of these targets/products is a test target/product and the other isn't.
            // Item 1 should come first iff item 2 is a test target/product.
            return item2Artifact.isTest
        }
        
        // Now sort in manifest declaration order.
        let item1ManifestIndex = context.manifestOrderByPackageAndName[package1]?[item1.name] ?? Int.max
        let item2ManifestIndex = context.manifestOrderByPackageAndName[package2]?[item2.name] ?? Int.max
        return item1ManifestIndex < item2ManifestIndex
    }
}

extension Collection where Element: TargetSortable {
    
    /// Sorts the collection of targets according to a target sort descriptor.
    ///
    /// - Parameter sortDescriptor: The target sort descriptor.
    /// - Returns: The sorted list of targets.
    func sorted(by sortDescriptor: TargetSortDescriptor) -> [Element] {
        return sorted(by: sortDescriptor.areInIncreasingOrder(_:_:))
    }
    
}
