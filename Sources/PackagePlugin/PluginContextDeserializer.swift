//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

typealias WireInput = HostToPluginMessage.InputContext

/// Deserializer for constructing a plugin input from the wire representation
/// received from SwiftPM, which consists of a set of flat lists of entities,
/// referenced by array index in all cross-references. The deserialized data
/// structure forms a directed acyclic graph. This information is provided to
/// the plugin in the `PluginContext` struct.
internal struct PluginContextDeserializer {
    let wireInput: WireInput
    var urlsById: [WireInput.URL.Id: URL] = [:]
    var packagesById: [WireInput.Package.Id: Package] = [:]
    var productsById: [WireInput.Product.Id: Product] = [:]
    var targetsById: [WireInput.Target.Id: Target] = [:]
    var xcodeProjectsById: [WireInput.XcodeProject.Id: XcodeProjectPluginInvocationRecord.XcodeProject] = [:]
    var xcodeTargetsById: [WireInput.XcodeTarget.Id: XcodeProjectPluginInvocationRecord.XcodeTarget] = [:]
    
    /// Initializes the deserializer with the given wire input.
    init(_ input: WireInput) {
        self.wireInput = input
    }
    
    /// Returns the `URL` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The URL is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func url(for id: WireInput.URL.Id) throws -> URL {
        if let path = urlsById[id] { return path }
        guard id < wireInput.paths.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid URL id (\(id))")
        }
        
        // Compose a path based on an optional base path and a subpath.
        let wirePath = wireInput.paths[id]
        let basePath = try wireInput.paths[id].baseURLId.map{ try self.url(for: $0) }
        let path: URL
        if let basePath {
            path = basePath.appendingPathComponent(wirePath.subpath)
        } else {
            #if os(Windows)
            // Windows does not have a single root path like UNIX, if this component has no base path, it IS the root and should not be joined with anything
            path = URL(fileURLWithPath: wirePath.subpath)
            #else
            path = URL(fileURLWithPath: "/").appendingPathComponent(wirePath.subpath)
            #endif
        }

        // Store it for the next look up.
        urlsById[id] = path
        return path
    }

    /// Returns the `Target` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The module is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func target(for id: WireInput.Target.Id, pluginGeneratedSources: [URL] = [], pluginGeneratedResources: [URL] = []) throws -> Target {
        if let target = targetsById[id],
           target.sourceModule?.pluginGeneratedSources.count == pluginGeneratedSources.count,
           target.sourceModule?.pluginGeneratedResources.count == pluginGeneratedResources.count {
            return target
        }
        guard id < wireInput.targets.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid target id (\(id))")
        }

        let wireTarget = wireInput.targets[id]
        let dependencies: [TargetDependency] = try wireTarget.dependencies.map {
            switch $0 {
            case .target(let targetId):
                let target = try self.target(for: targetId)
                return .target(target)
            case .product(let productId):
                let product = try self.product(for: productId)
                return .product(product)
            }
        }
        let directory = try self.url(for: wireTarget.directoryId)
        let target: Target
        switch wireTarget.info {
        
        case let .swiftSourceModuleInfo(moduleName, kind, sourceFiles, compilationConditions, linkedLibraries, linkedFrameworks):
            let sourceFiles = FileList(try sourceFiles.map {
                let path = try self.url(for: $0.basePathId).appendingPathComponent($0.name)
                let type: FileType
                switch $0.type {
                case .source:
                    type = .source
                case .header:
                    type = .header
                case .resource:
                    type = .resource
                case .unknown:
                    type = .unknown
                }
                return File(url: path, type: type)
            })
            target = try SwiftSourceModuleTarget(
                id: String(id),
                name: wireTarget.name,
                kind: .init(kind),
                directory: Path(url: directory),
                directoryURL: directory,
                dependencies: dependencies,
                moduleName: moduleName,
                sourceFiles: sourceFiles,
                compilationConditions: compilationConditions,
                linkedLibraries: linkedLibraries,
                linkedFrameworks: linkedFrameworks,
                pluginGeneratedSources: pluginGeneratedSources,
                pluginGeneratedResources: pluginGeneratedResources
            )

        case let .clangSourceModuleInfo(moduleName, kind, sourceFiles, preprocessorDefinitions, headerSearchPaths, publicHeadersDirId, linkedLibraries, linkedFrameworks):
            let publicHeadersDir = try publicHeadersDirId.map { try self.url(for: $0) }
            let sourceFiles = FileList(try sourceFiles.map {
                let path = try self.url(for: $0.basePathId).appendingPathComponent($0.name)
                let type: FileType
                switch $0.type {
                case .source:
                    type = .source
                case .header:
                    type = .header
                case .resource:
                    type = .resource
                case .unknown:
                    type = .unknown
                }
                return File(url: path, type: type)
            })
            target = try ClangSourceModuleTarget(
                id: String(id),
                name: wireTarget.name,
                kind: .init(kind),
                directory: Path(url: directory),
                directoryURL: directory,
                dependencies: dependencies,
                moduleName: moduleName,
                sourceFiles: sourceFiles,
                preprocessorDefinitions: preprocessorDefinitions,
                headerSearchPaths: headerSearchPaths,
                publicHeadersDirectory: publicHeadersDir.map { try .init(url: $0) },
                publicHeadersDirectoryURL: publicHeadersDir,
                linkedLibraries: linkedLibraries,
                linkedFrameworks: linkedFrameworks,
                pluginGeneratedSources: pluginGeneratedSources,
                pluginGeneratedResources: pluginGeneratedResources
            )

        case let .binaryArtifactInfo(kind, origin, artifactId):
            let artifact = try self.url(for: artifactId)
            let artifactKind: BinaryArtifactTarget.Kind
            switch kind {
            case .artifactsArchive:
                artifactKind = .artifactsArchive
            case .xcframework:
                artifactKind = .xcframework
            }
            let artifactOrigin: BinaryArtifactTarget.Origin
            switch origin {
            case .local:
                artifactOrigin = .local
            case .remote(let url):
                artifactOrigin = .remote(url: url)
            }
            target = try BinaryArtifactTarget(
                id: String(id),
                name: wireTarget.name,
                directory: Path(url: directory),
                directoryURL: directory,
                dependencies: dependencies,
                kind: artifactKind,
                origin: artifactOrigin,
                artifact: Path(url: artifact),
                artifactURL: artifact)

        case let .systemLibraryInfo(pkgConfig, compilerFlags, linkerFlags):
            target = try SystemLibraryTarget(
                id: String(id),
                name: wireTarget.name,
                directory: Path(url: directory),
                directoryURL: directory,
                dependencies: dependencies,
                pkgConfig: pkgConfig,
                compilerFlags: compilerFlags,
                linkerFlags: linkerFlags)
        }
        
        targetsById[id] = target
        return target
    }

    /// Returns the `Product` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The product is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func product(for id: WireInput.Product.Id) throws -> Product {
        if let product = productsById[id] { return product }
        guard id < wireInput.products.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid product id (\(id))")
        }

        let wireProduct = wireInput.products[id]
        let targets: [Target] = try wireProduct.targetIds.map{ try self.target(for: $0) }
        let product: Product
        switch wireProduct.info {

        case .executable(let mainTargetId):
            let mainTarget = try self.target(for: mainTargetId)
            product = ExecutableProduct(
                id: String(id),
                name: wireProduct.name,
                targets: targets,
                mainTarget: mainTarget)

        case .library(let type):
            let libraryKind: LibraryProduct.Kind
            switch type {
            case .static:
                libraryKind = .static
            case .dynamic:
                libraryKind = .dynamic
            case .automatic:
                libraryKind = .automatic
            }
            product = LibraryProduct(
                id: String(id),
                name: wireProduct.name,
                targets: targets,
                kind: libraryKind)
        }
        
        productsById[id] = product
        return product
    }

    /// Returns the `Package` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The package is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func package(for id: WireInput.Product.Id) throws -> Package {
        if let package = packagesById[id] { return package }
        guard id < wireInput.packages.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid package id (\(id))") }
        
        let wirePackage = wireInput.packages[id]
        let directory = try self.url(for: wirePackage.directoryId)
        let toolsVersion = ToolsVersion(
            major: wirePackage.toolsVersion.major,
            minor: wirePackage.toolsVersion.minor,
            patch: wirePackage.toolsVersion.patch)
        let dependencies: [PackageDependency] = try wirePackage.dependencies.map {
            .init(package: try self.package(for: $0.packageId))
        }
        let products = try wirePackage.productIds.map { try self.product(for: $0) }
        let targets = try wirePackage.targetIds.map { try self.target(for: $0) }
        let origin: PackageOrigin = switch wirePackage.origin {
            case .root:
                .root
            case .local(let pathId):
                try .local(path: url(for: pathId).path)
            case .repository(let url, let displayVersion, let scmRevision):
                .repository(url: url, displayVersion: displayVersion, scmRevision: scmRevision)
            case .registry(let identity, let displayVersion):
                .registry(identity: identity, displayVersion: displayVersion)
        }
        let package = try Package(
            id: wirePackage.identity,
            displayName: wirePackage.displayName,
            directory: Path(url: directory),
            directoryURL: directory,
            origin:  origin,
            toolsVersion: toolsVersion,
            dependencies: dependencies,
            products: products,
            targets: targets)
        
        packagesById[id] = package
        return package
    }

    /// Returns the `XcodeTarget` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The product is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func xcodeTarget(for id: WireInput.XcodeTarget.Id, pluginGeneratedSources: [URL] = [], pluginGeneratedResources: [URL] = []) throws -> XcodeProjectPluginInvocationRecord.XcodeTarget {
        if let xcodeTarget = xcodeTargetsById[id],
           xcodeTarget.pluginGeneratedSources.count == pluginGeneratedSources.count,
           xcodeTarget.pluginGeneratedResources.count == pluginGeneratedResources.count {
            return xcodeTarget
        }
        guard id < wireInput.xcodeTargets.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid Xcode target id (\(id))")
        }

        let wireXcodeTarget = wireInput.xcodeTargets[id]
        let product: XcodeProjectPluginInvocationRecord.XcodeTarget.Product? = wireXcodeTarget.product.map {
            let kind: XcodeProjectPluginInvocationRecord.XcodeTarget.Product.Kind
            switch $0.kind {
            case .application:
                kind = .application
            case .executable:
                kind = .executable
            case .framework:
                kind = .framework
            case .library:
                kind = .library
            case .other(let ident):
                kind = .other(ident)
            }
            return .init(name: $0.name, kind: kind)
        }
        let inputFiles = FileList(try wireXcodeTarget.inputFiles.map {
            let path = try self.url(for: $0.basePathId).appendingPathComponent($0.name)
            let type: FileType
            switch $0.type {
            case .source:
                type = .source
            case .header:
                type = .header
            case .resource:
                type = .resource
            case .unknown:
                type = .unknown
            }
            return .init(url: path, type: type)
        })
        let xcodeTarget = XcodeProjectPluginInvocationRecord.XcodeTarget(
            id: String(id),
            displayName: wireXcodeTarget.displayName,
            product: product,
            inputFiles: inputFiles,
            pluginGeneratedSources: pluginGeneratedSources,
            pluginGeneratedResources: pluginGeneratedResources
        )

        xcodeTargetsById[id] = xcodeTarget
        return xcodeTarget
    }

    /// Returns the `Package` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The package is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func xcodeProject(for id: WireInput.XcodeProject.Id) throws -> XcodeProjectPluginInvocationRecord.XcodeProject {
        if let xcodeProject = xcodeProjectsById[id] { return xcodeProject }
        guard id < wireInput.xcodeProjects.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid Xcode project id (\(id))") }
        
        let wireXcodeProject = wireInput.xcodeProjects[id]
        let directoryPath = try self.url(for: wireXcodeProject.directoryPathId)
        let filePaths = PathList(try wireXcodeProject.urlIds.map{ try self.url(for: $0) })
        let targets = try wireXcodeProject.targetIds.map { try self.xcodeTarget(for: $0) }
        let xcodeProject = XcodeProjectPluginInvocationRecord.XcodeProject(
            id: String(id),
            displayName: wireXcodeProject.displayName,
            directoryPathURL: directoryPath,
            filePaths: filePaths,
            targets: targets)
        
        xcodeProjectsById[id] = xcodeProject
        return xcodeProject
    }
}

fileprivate extension ModuleKind {
    init(_ kind: WireInput.Target.TargetInfo.SourceModuleKind) {
        switch kind {
        case .generic:
            self = .generic
        case .executable:
            self = .executable
        case .snippet:
            self = .snippet
        case .test:
            self = .test
        case .macro:
            self = .macro
        }
    }
}
