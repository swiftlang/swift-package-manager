//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// In this file, only import modules that are part of SwiftPMDataModel (or swift-tools-support-core)!
// This way, we cannot accidentally use unavailable types in the API intended for clients.
@_exported import PackageGraph
@_exported import PackageModel
@_exported import struct TSCBasic.AbsolutePath
@_exported import Workspace

// Modules not part of SwiftPMDataModel may be imported with @_implementationOnly.
@_implementationOnly import Basics

extension Workspace {

    /// Loads a manifest as the root manifest of the workspace.
    ///
    /// This method is most easily used with `tsc_await` from the `TSCBasic` module in the `swift-tools-support-core` package:
    ///
    /// ```swift
    /// let manifest = try tsc_await { completion in
    ///     someWorkspace.loadRootManifest(
    ///         at: somePath,
    ///         diagnosticObserver: someObserver,
    ///         completion: completion
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///     - path: The path to the package’s root directory.
    ///     - diagnosticObserver: An observer to handle diagnostics.
    ///     - completion: A closure that will be executed when the loading is complete (or has failed).
    public func loadRootManifest(
        at path: AbsolutePath,
        diagnosticObserver: DiagnosticObserver,
        completion: @escaping(Result<Manifest, Error>) -> Void
    ) {
        return loadRootManifest(
            at: path,
            observabilityScope: diagnosticObserver.observabilitySystem.topScope,
            completion: completion
        )
    }

    /// Loads a package as the root package of the workspace.
    ///
    /// This method is most easily used with `tsc_await` from the `TSCBasic` module in the `swift-tools-support-core` package:
    ///
    /// ```swift
    /// let package = try tsc_await { completion in
    ///     someWorkspace.loadRootPackage(
    ///         at: somePath,
    ///         diagnosticObserver: someObserver,
    ///         completion: completion
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///     - path: The path to the package’s root directory.
    ///     - diagnosticObserver: An observer to handle diagnostics.
    ///     - completion: A closure that will be executed when the loading is complete (or has failed).
    public func loadRootPackage(
        at path: AbsolutePath,
        diagnosticObserver: DiagnosticObserver,
        completion: @escaping(Result<Package, Error>) -> Void
    ) {
        return loadRootPackage(
            at: path,
            observabilityScope: diagnosticObserver.observabilitySystem.topScope,
            completion: completion
        )
    }

    /// Loads the dependency graph of a package as the root package of the workspace.
    ///
    /// - Parameters:
    ///     - rootPath: The path to the package’s root directory.
    ///     - explicitProduct: Optional; a string may be passed in order to simulate an explicit product name being supplied to the command line (which may affect the resolution of immediate dependencies by causing the inclusion of an otherwise unused product).
    ///     - diagnosticObserver: An observer to handle diagnostics.
    public func loadPackageGraph(
        rootPath: AbsolutePath,
        explicitProduct: String? = nil,
        diagnosticObserver: DiagnosticObserver
    ) throws -> PackageGraph {
        return try loadPackageGraph(
            rootPath: rootPath,
            explicitProduct: explicitProduct,
            observabilityScope: diagnosticObserver.observabilitySystem.topScope
        )
    }
}

/// An observer that handles diagnostics emitted while a workspace is loading its components.
public struct DiagnosticObserver {

    fileprivate let observabilitySystem: ObservabilitySystem

    /// Creates a diagnostic observer.
    ///
    /// - Parameters:
    ///     - handler: A closure that will be executed each time a diagnostic is emitted.
    ///     - scope: The label of the scope where the diagnostic was emmitted.
    ///     - diagnostic: The diagnostic message.
    public init(_ handler: @escaping (_ scope: String, _ diagnostic: String) -> Void) {
        observabilitySystem = ObservabilitySystem(
            { (scope: ObservabilityScope, diagnostic: Basics.Diagnostic) -> Void in
                handler(
                  String(describing: scope),
                  String(describing: diagnostic)
                )
            }
        )
    }
}
