/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

public final class ResolvedProduct: ObjectIdentifierProtocol {

    /// The underlying product.
    public let underlyingProduct: Product

    /// The name of this product.
    public var name: String {
        return underlyingProduct.name
    }

    /// The top level targets contained in this product.
    public let targets: [ResolvedTarget]

    /// The type of this product.
    public var type: ProductType {
        return underlyingProduct.type
    }

    /// Executable target for linux main test manifest file.
    public let linuxMainTarget: ResolvedTarget?

    /// The main executable target of product.
    ///
    /// Note: This property is only valid for executable products.
    public var executableModule: ResolvedTarget {
        precondition(type == .executable, "This property should only be called for executable targets")
        return targets.first(where: { $0.type == .executable })!
    }

    public init(product: Product, targets: [ResolvedTarget]) {
        assert(product.targets.count == targets.count && product.targets.map({ $0.name }) == targets.map({ $0.name }))
        self.underlyingProduct = product
        self.targets = targets

        self.linuxMainTarget = underlyingProduct.linuxMain.map({ linuxMain in
            // Create an executable resolved target with the linux main, adding product's targets as dependencies.
            let dependencies: [Target.Dependency] = product.targets.map { .target($0, conditions: []) }
            let swiftTarget = SwiftTarget(linuxMain: linuxMain, name: product.name, dependencies: dependencies)
            return ResolvedTarget(target: swiftTarget, dependencies: targets.map { .target($0, conditions: []) })
        })
    }

    /// True if this product contains Swift targets.
    public var containsSwiftTargets: Bool {
      //  C targets can't import Swift targets in SwiftPM (at least not right
      // now), so we can just look at the top-level targets.
      //
      // If that ever changes, we'll need to do something more complex here,
      // recursively checking dependencies for SwiftTargets, and considering
      // dynamic library targets to be Swift targets (since the dylib could
      // contain Swift code we don't know about as part of this build).
      return targets.contains { $0.underlyingTarget is SwiftTarget }
    }

    /// Returns the recursive target dependencies.
    public func recursiveTargetDependencies() -> [ResolvedTarget] {
        let recursiveDependencies = targets.lazy.flatMap { $0.recursiveTargetDependencies() }
        return Array(Set(targets).union(recursiveDependencies))
    }
}

extension ResolvedProduct: CustomStringConvertible {
    public var description: String {
        return "<ResolvedProduct: \(name)>"
    }
}

fileprivate extension SwiftTarget {
    /// Create an executable Swift target from linux main test manifest file.
    convenience init(linuxMain: AbsolutePath, name: String, dependencies: [Target.Dependency]) {
        // Look for the first swift test target and use the same swift version
        // for linux main target. This will need to change if we move to a model
        // where we allow per target swift language version build settings.
        let swiftTestTarget = dependencies.first {
            guard case .target(let target as SwiftTarget, _) = $0 else { return false }
            return target.type == .test
        }.flatMap { $0.target as? SwiftTarget }

        // FIXME: This is not very correct but doesn't matter much in practice.
        // We need to select the latest Swift language version that can
        // satisfy the current tools version but there is not a good way to
        // do that currently.
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)

        let platforms: [SupportedPlatform] = swiftTestTarget?.platforms ?? []

        let swiftVersion = swiftTestTarget?.swiftVersion ?? SwiftLanguageVersion(string: String(ToolsVersion.currentToolsVersion.major)) ?? .v4

        self.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            sources: sources,
            dependencies: dependencies,
            swiftVersion: swiftVersion,
            buildSettings: .init()
        )
    }
}
