/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@_implementationOnly import Foundation

/// Input information to the plugin, constructed by decoding and deserializing
/// the JSON data received from SwiftPM.
struct PluginInput {
    let package: Package
    let pluginWorkDirectory: Path
    let builtProductsDirectory: Path
    let toolSearchDirectories: [Path]
    let toolNamesToPaths: [String: Path]
    let pluginAction: PluginAction
    enum PluginAction {
        case createBuildToolCommands(target: Target)
        case performCommand(targets: [Target], arguments: [String])
    }
    
    internal init(from input: WireInput) throws {
        // Create a deserializer to unpack the input structures.
        var deserializer = PluginInputDeserializer(with: input)
        
        // Unpack the individual pieces from which we'll create the plugin context.
        self.package = try deserializer.package(for: input.rootPackageId)
        self.pluginWorkDirectory = try deserializer.path(for: input.pluginWorkDirId)
        self.builtProductsDirectory = try deserializer.path(for: input.builtProductsDirId)
        self.toolSearchDirectories = try input.toolSearchDirIds.map { try deserializer.path(for: $0) }
        self.toolNamesToPaths = try input.toolNamesToPathIds.mapValues { try deserializer.path(for: $0) }
        
        // Unpack the plugin action, which will determine which plugin functionality to invoke.
        switch input.pluginAction {
        case .createBuildToolCommands(let targetId):
            self.pluginAction = .createBuildToolCommands(target: try deserializer.target(for: targetId))
        case .performCommand(let targetIds, let arguments):
            self.pluginAction = .performCommand(targets: try targetIds.map{ try deserializer.target(for: $0) }, arguments: arguments)
        }
    }
}

/// Deserializer for constructing a plugin input from the wire representation
/// received from SwiftPM, which consists of a set of flat lists of entities,
/// referenced by array index in all cross-references. The deserialized data
/// structure forms a directed acyclic graph.
fileprivate struct PluginInputDeserializer {
    let input: WireInput
    var pathsById: [WireInput.Path.Id: Path] = [:]
    var packagesById: [WireInput.Package.Id: Package] = [:]
    var productsById: [WireInput.Product.Id: Product] = [:]
    var targetsById: [WireInput.Target.Id: Target] = [:]
    
    /// Initializes the deserializer with the given wire input.
    fileprivate init(with input: WireInput) {
        self.input = input
    }
    
    /// Returns the `Path` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The path is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func path(for id: WireInput.Path.Id) throws -> Path {
        if let path = pathsById[id] { return path }
        guard id < input.paths.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid path id (\(id))")
        }
        
        // Compose a path based on an optional base path and a subpath.
        let wirePath = input.paths[id]
        let basePath = try input.paths[id].basePathId.map{ try self.path(for: $0) } ?? Path("/")
        let path = basePath.appending(subpath: wirePath.subpath)
        
        // Store it for the next look up.
        pathsById[id] = path
        return path
    }

    /// Returns the `Target` that corresponds to the given ID (a small integer),
    /// or throws an error if the ID is invalid. The target is deserialized on-
    /// demand if it hasn't already been deserialized.
    mutating func target(for id: WireInput.Target.Id) throws -> Target {
        if let target = targetsById[id] { return target }
        guard id < input.targets.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid target id (\(id))")
        }

        let wireTarget = input.targets[id]
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
        let directory = try self.path(for: wireTarget.directoryId)
        let target: Target
        switch wireTarget.info {
        
        case let .swiftSourceModuleInfo(moduleName, sourceFiles, compilationConditions, linkedLibraries, linkedFrameworks):
            let sourceFiles = FileList(try sourceFiles.map {
                let path = try self.path(for: $0.basePathId).appending($0.name)
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
                return File(path: path, type: type)
            })
            target = SwiftSourceModuleTarget(
                id: String(id),
                name: wireTarget.name,
                directory: directory,
                dependencies: dependencies,
                moduleName: moduleName,
                sourceFiles: sourceFiles,
                compilationConditions: compilationConditions,
                linkedLibraries: linkedLibraries,
                linkedFrameworks: linkedFrameworks)

        case let .clangSourceModuleInfo(moduleName, sourceFiles, preprocessorDefinitions, headerSearchPaths, publicHeadersDirId, linkedLibraries, linkedFrameworks):
            let publicHeadersDir = try publicHeadersDirId.map { try self.path(for: $0) }
            let sourceFiles = FileList(try sourceFiles.map {
                let path = try self.path(for: $0.basePathId).appending($0.name)
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
                return File(path: path, type: type)
            })
            target = ClangSourceModuleTarget(
                id: String(id),
                name: wireTarget.name,
                directory: directory,
                dependencies: dependencies,
                moduleName: moduleName,
                sourceFiles: sourceFiles,
                preprocessorDefinitions: preprocessorDefinitions,
                headerSearchPaths: headerSearchPaths,
                publicHeadersDirectory: publicHeadersDir,
                linkedLibraries: linkedLibraries,
                linkedFrameworks: linkedFrameworks)

        case let .binaryArtifactInfo(kind, origin, artifactId):
            let artifact = try self.path(for: artifactId)
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
            target = BinaryArtifactTarget(
                id: String(id),
                name: wireTarget.name,
                directory: directory,
                dependencies: dependencies,
                kind: artifactKind,
                origin: artifactOrigin,
                artifact: artifact)

        case let .systemLibraryInfo(pkgConfig, compilerFlags, linkerFlags):
            target = SystemLibraryTarget(
                id: String(id),
                name: wireTarget.name,
                directory: directory,
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
        guard id < input.products.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid product id (\(id))")
        }

        let wireProduct = input.products[id]
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
        guard id < input.packages.count else {
            throw PluginDeserializationError.malformedInputJSON("invalid package id (\(id))") }
        
        let wirePackage = input.packages[id]
        let directory = try self.path(for: wirePackage.directoryId)
        let toolsVersion = ToolsVersion(
            major: wirePackage.toolsVersion.major,
            minor: wirePackage.toolsVersion.minor,
            patch: wirePackage.toolsVersion.patch)
        let dependencies: [PackageDependency] = try wirePackage.dependencies.map {
            .init(package: try self.package(for: $0.packageId))
        }
        let products = try wirePackage.productIds.map { try self.product(for: $0) }
        let targets = try wirePackage.targetIds.map { try self.target(for: $0) }
        let package = Package(
            id: wirePackage.identity,
            displayName: wirePackage.displayName,
            directory: directory,
            origin: .root,
            toolsVersion: toolsVersion,
            dependencies: dependencies,
            products: products,
            targets: targets)
        
        packagesById[id] = package
        return package
    }
}

/// The input structure received as JSON from SwiftPM, consisting of an array
/// of flat structures for each kind of entity. All references to entities use
/// ID numbers that correspond to the indices into these arrays. The directed
/// acyclic graph is then deserialized from this structure.
internal struct WireInput: Decodable {
    let paths: [Path]
    let targets: [Target]
    let products: [Product]
    let packages: [Package]
    let rootPackageId: Package.Id
    let pluginWorkDirId: Path.Id
    let builtProductsDirId: Path.Id
    let toolSearchDirIds: [Path.Id]
    let toolNamesToPathIds: [String: Path.Id]
    let pluginAction: PluginAction

    /// An action that SwiftPM can ask the plugin to take. This corresponds to
    /// the capabilities declared for the plugin.
    enum PluginAction: Decodable {
        case createBuildToolCommands(targetId: Target.Id)
        case performCommand(targetIds: [Target.Id], arguments: [String])
    }

    /// A single absolute path in the wire structure, represented as a tuple
    /// consisting of the ID of the base path and subpath off of that path.
    /// This avoids repetition of path components in the wire representation.
    struct Path: Decodable {
        typealias Id = Int
        let basePathId: Path.Id?
        let subpath: String
    }

    /// A package in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Package: Decodable {
        typealias Id = Int
        let identity: String
        let displayName: String
        let directoryId: Path.Id
        let origin: Origin
        let toolsVersion: ToolsVersion
        let dependencies: [Dependency]
        let productIds: [Product.Id]
        let targetIds: [Target.Id]

        /// The origin of the package (root, local, repository, registry, etc).
        enum Origin: Decodable {
            case root
            case local(
                path: Path.Id)
            case repository(
                url: String,
                displayVersion: String,
                scmRevision: String)
            case registry(
                identity: String,
                displayVersion: String)
        }
        
        /// Represents a version of SwiftPM on whose semantics a package relies.
        struct ToolsVersion: Decodable {
            let major: Int
            let minor: Int
            let patch: Int
        }

        /// A dependency on a package in the wire structure. All references to
        /// other entities are ID numbers.
        struct Dependency: Decodable {
            let packageId: Package.Id
        }
    }

    /// A product in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Product: Decodable {
        typealias Id = Int
        let name: String
        let targetIds: [Target.Id]
        let info: ProductInfo

        /// Information for each type of product in the wire structure. All
        /// references to other entities are their ID numbers.
        enum ProductInfo: Decodable {
            case executable(
                mainTargetId: Target.Id)
            case library(
                kind: LibraryKind)

            /// A type of library in the wire structure, as SwiftPM sees it.
            enum LibraryKind: Decodable {
                case `static`
                case `dynamic`
                case automatic
            }
        }
    }

    /// A target in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Target: Decodable {
        typealias Id = Int
        let name: String
        let directoryId: Path.Id
        let dependencies: [Dependency]
        let info: TargetInfo

        /// A dependency on either a target or a product in the wire structure.
        /// All references to other entities are ID their numbers.
        enum Dependency: Decodable {
            case target(
                targetId: Target.Id)
            case product(
                productId: Product.Id)
        }
        
        /// Type-specific information for a target in the wire structure. All
        /// references to other entities are their ID numbers.
        enum TargetInfo: Decodable {
            /// Information about a Swift source module target.
            case swiftSourceModuleInfo(
                moduleName: String,
                sourceFiles: [File],
                compilationConditions: [String],
                linkedLibraries: [String],
                linkedFrameworks: [String])
            
            /// Information about a Clang source module target.
            case clangSourceModuleInfo(
                moduleName: String,
                sourceFiles: [File],
                preprocessorDefinitions: [String],
                headerSearchPaths: [String],
                publicHeadersDirId: Path.Id?,
                linkedLibraries: [String],
                linkedFrameworks: [String])
            
            /// Information about a binary artifact target.
            case binaryArtifactInfo(
                kind: BinaryArtifactKind,
                origin: BinaryArtifactOrigin,
                artifactId: Path.Id)
            
            /// Information about a system library target.
            case systemLibraryInfo(
                pkgConfig: String?,
                compilerFlags: [String],
                linkerFlags: [String])

            /// A file in the wire structure.
            struct File: Decodable {
                let basePathId: Path.Id
                let name: String
                let type: FileType

                /// A type of file in the wire structure, as SwiftPM sees it.
                enum FileType: String, Decodable {
                    case source
                    case header
                    case resource
                    case unknown
                }
            }

            enum BinaryArtifactKind: Decodable {
                case xcframework
                case artifactsArchive
            }

            enum BinaryArtifactOrigin: Decodable {
                case local
                case remote(url: String)
            }
        }
    }
}
