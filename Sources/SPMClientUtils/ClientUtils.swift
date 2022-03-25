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

public struct DiagnosticObserver {

    fileprivate let observabilitySystem: ObservabilitySystem

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
