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
    /// - Parameters:
    ///     - path: The path to the package’s root directory.
    ///     - diagnosticObserver: An observer to handle diagnostics.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    public func loadRootManifest(
        at path: AbsolutePath,
        diagnosticObserver: DiagnosticObserver
    ) async throws -> Manifest {
        return try await loadRootManifest(
            at: path,
            observabilityScope: diagnosticObserver.observabilitySystem.topScope
        )
    }

    /// Loads a package as the root package of the workspace.
    ///
    /// - Parameters:
    ///     - path: The path to the package’s root directory.
    ///     - diagnosticObserver: An observer to handle diagnostics.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    public func loadRootPackage(
        at path: AbsolutePath,
        diagnosticObserver: DiagnosticObserver
    ) async throws -> Package {
        return try await loadRootPackage(
            at: path,
            observabilityScope: diagnosticObserver.observabilitySystem.topScope
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
    /// Diagnostics may be produced from any thread and multiple closure executions may overlap. Be aware of the concurrency ramifications for any context captured by the closure.
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
