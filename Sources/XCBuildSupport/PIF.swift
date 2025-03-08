//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import OrderedCollections
import PackageModel

import struct TSCBasic.ByteString

/// The Project Interchange Format (PIF) is a structured representation of the
/// project model created by clients (Xcode/SwiftPM) to send to XCBuild.
///
/// The PIF is a representation of the project model describing the static
/// objects which contribute to building products from the project, independent
/// of "how" the user has chosen to build those products in any particular
/// build. This information can be cached by XCBuild between builds (even
/// between builds which use different schemes or configurations), and can be
/// incrementally updated by clients when something changes.
public enum PIF {
    /// This is used as part of the signature for the high-level PIF objects, to ensure that changes to the PIF schema
    /// are represented by the objects which do not use a content-based signature scheme (workspaces and projects,
    /// currently).
    static let schemaVersion = 11

    /// The type used for identifying PIF objects.
    public typealias GUID = String

    /// The top-level PIF object.
    public struct TopLevelObject: Encodable {
        public let workspace: PIF.Workspace

        public init(workspace: PIF.Workspace) {
            self.workspace = workspace
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()

            // Encode the workspace.
            try container.encode(workspace)

            // Encode the projects and their targets.
            for project in workspace.projects {
                try container.encode(project)

                for target in project.targets {
                    try container.encode(target)
                }
            }
        }
    }

    public class TypedObject: Codable {
        class var type: String {
            fatalError("\(self) missing implementation")
        }

        let type: String?

        fileprivate init() {
            type = Swift.type(of: self).type
        }

        private enum CodingKeys: CodingKey {
            case type
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Swift.type(of: self).type, forKey: .type)
        }

        required public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
        }
    }

    public final class Workspace: TypedObject {
        override class var type: String { "workspace" }

        public let guid: GUID
        public var name: String
        public var path: AbsolutePath
        public var projects: [Project]
        var signature: String?

        public init(guid: GUID,  name: String, path: AbsolutePath, projects: [Project]) {
            precondition(!guid.isEmpty)
            precondition(!name.isEmpty)
            precondition(Set(projects.map({ $0.guid })).count == projects.count)

            self.guid = guid
            self.name = name
            self.path = path
            self.projects = projects
            super.init()
        }

        private enum CodingKeys: CodingKey {
            case guid, name, path, projects, signature
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: StringKey.self)
            var contents = container.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")
            try contents.encode("\(guid)@\(schemaVersion)", forKey: .guid)
            try contents.encode(name, forKey: .name)
            try contents.encode(path, forKey: .path)

            if encoder.userInfo.keys.contains(.encodeForXCBuild) {
                guard let signature else {
                    throw InternalError("Expected to have workspace signature when encoding for XCBuild")
                }
                try container.encode(signature, forKey: "signature")
                try contents.encode(projects.map({ $0.signature }), forKey: .projects)
            } else {
                try contents.encode(projects, forKey: .projects)
            }
        }

        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: StringKey.self)
            let container = try superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")

            let guidString = try container.decode(GUID.self, forKey: .guid)
            self.guid = String(guidString.dropLast("\(schemaVersion)".count + 1))
            self.name = try container.decode(String.self, forKey: .name)
            self.path = try container.decode(AbsolutePath.self, forKey: .path)
            self.projects = try container.decode([Project].self, forKey: .projects)
            try super.init(from: decoder)
        }
    }

    /// A PIF project, consisting of a tree of groups and file references, a list of targets, and some additional
    /// information.
    public final class Project: TypedObject {
        override class var type: String { "project" }

        public let guid: GUID
        public var name: String
        public var path: AbsolutePath
        public var projectDirectory: AbsolutePath
        public var developmentRegion: String
        public var buildConfigurations: [BuildConfiguration]
        public var targets: [BaseTarget]
        public var groupTree: Group
        var signature: String?

        public init(
            guid: GUID,
            name: String,
            path: AbsolutePath,
            projectDirectory: AbsolutePath,
            developmentRegion: String,
            buildConfigurations: [BuildConfiguration],
            targets: [BaseTarget],
            groupTree: Group
        ) {
            precondition(!guid.isEmpty)
            precondition(!name.isEmpty)
            precondition(!developmentRegion.isEmpty)
            precondition(Set(targets.map({ $0.guid })).count == targets.count)
            precondition(Set(buildConfigurations.map({ $0.guid })).count == buildConfigurations.count)

            self.guid = guid
            self.name = name
            self.path = path
            self.projectDirectory = projectDirectory
            self.developmentRegion = developmentRegion
            self.buildConfigurations = buildConfigurations
            self.targets = targets
            self.groupTree = groupTree
            super.init()
        }

        private enum CodingKeys: CodingKey {
            case guid, projectName, projectIsPackage, path, projectDirectory, developmentRegion, defaultConfigurationName, buildConfigurations, targets, groupTree, signature
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: StringKey.self)
            var contents = container.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")
            try contents.encode("\(guid)@\(schemaVersion)", forKey: .guid)
            try contents.encode(name, forKey: .projectName)
            try contents.encode("true", forKey: .projectIsPackage)
            try contents.encode(path, forKey: .path)
            try contents.encode(projectDirectory, forKey: .projectDirectory)
            try contents.encode(developmentRegion, forKey: .developmentRegion)
            try contents.encode("Release", forKey: .defaultConfigurationName)
            try contents.encode(buildConfigurations, forKey: .buildConfigurations)

            if encoder.userInfo.keys.contains(.encodeForXCBuild) {
                guard let signature else {
                    throw InternalError("Expected to have project signature when encoding for XCBuild")
                }
                try container.encode(signature, forKey: "signature")
                try contents.encode(targets.map{ $0.signature }, forKey: .targets)
            } else {
                try contents.encode(targets, forKey: .targets)
            }

            try contents.encode(groupTree, forKey: .groupTree)
        }

        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: StringKey.self)
            let container = try superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")

            let guidString = try container.decode(GUID.self, forKey: .guid)
            self.guid = String(guidString.dropLast("\(schemaVersion)".count + 1))
            self.name = try container.decode(String.self, forKey: .projectName)
            self.path = try container.decode(AbsolutePath.self, forKey: .path)
            self.projectDirectory = try container.decode(AbsolutePath.self, forKey: .projectDirectory)
            self.developmentRegion = try container.decode(String.self, forKey: .developmentRegion)
            self.buildConfigurations = try container.decode([BuildConfiguration].self, forKey: .buildConfigurations)

            let untypedTargets = try container.decode([UntypedTarget].self, forKey: .targets)
            var targetContainer = try container.nestedUnkeyedContainer(forKey: .targets)
            self.targets = try untypedTargets.map { target in
                let type = target.contents.type
                switch type {
                case "aggregate":
                    return try targetContainer.decode(AggregateTarget.self)
                case "standard", "packageProduct":
                    return try targetContainer.decode(Target.self)
                default:
                    throw InternalError("unknown target type \(type)")
                }
            }

            self.groupTree = try container.decode(Group.self, forKey: .groupTree)
            try super.init(from: decoder)
        }
    }

    /// Abstract base class for all items in the group hierarchy.
    public class Reference: TypedObject {
        /// Determines the base path for a reference's relative path.
        public enum SourceTree: String, Codable {

            /// Indicates that the path is relative to the source root (i.e. the "project directory").
            case sourceRoot = "SOURCE_ROOT"

            /// Indicates that the path is relative to the path of the parent group.
            case group = "<group>"

            /// Indicates that the path is relative to the effective build directory (which varies depending on active
            /// scheme, active run destination, or even an overridden build setting.
            case builtProductsDir = "BUILT_PRODUCTS_DIR"

            /// Indicates that the path is an absolute path.
            case absolute = "<absolute>"
        }

        public let guid: GUID

        /// Relative path of the reference.  It is usually a literal, but may in fact contain build settings.
        public var path: String

        /// Determines the base path for the reference's relative path.
        public var sourceTree: SourceTree

        /// Name of the reference, if different from the last path component (if not set, the last path component will
        /// be used as the name).
        public var name: String?

        fileprivate init(
            guid: GUID,
            path: String,
            sourceTree: SourceTree,
            name: String?
        ) {
            precondition(!guid.isEmpty)
            precondition(!(name?.isEmpty ?? false))

            self.guid = guid
            self.path = path
            self.sourceTree = sourceTree
            self.name = name
            super.init()
        }

        private enum CodingKeys: CodingKey {
            case guid, sourceTree, path, name, type
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(guid, forKey: .guid)
            try container.encode(sourceTree, forKey: .sourceTree)
            try container.encode(path, forKey: .path)
            try container.encode(name ?? path, forKey: .name)
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.guid = try container.decode(String.self, forKey: .guid)
            self.sourceTree = try container.decode(SourceTree.self, forKey: .sourceTree)
            self.path = try container.decode(String.self, forKey: .path)
            self.name = try container.decodeIfPresent(String.self, forKey: .name)
            try super.init(from: decoder)
        }
    }

    /// A reference to a file system entity (a file, folder, etc).
    public final class FileReference: Reference {
        override class var type: String { "file" }

        public var fileType: String

        public init(
            guid: GUID,
            path: String,
            sourceTree: SourceTree = .group,
            name: String? = nil,
            fileType: String? = nil
        ) {
            self.fileType = fileType ?? FileReference.fileTypeIdentifier(forPath: path)
            super.init(guid: guid, path: path, sourceTree: sourceTree, name: name)
        }

        private enum CodingKeys: CodingKey {
            case fileType
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fileType, forKey: .fileType)
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.fileType = try container.decode(String.self, forKey: .fileType)
            try super.init(from: decoder)
        }
    }

    /// A group that can contain References (FileReferences and other Groups). The resolved path of a group is used as
    /// the base path for any child references whose source tree type is GroupRelative.
    public final class Group: Reference {
        override class var type: String { "group" }

        public var children: [Reference]

        public init(
            guid: GUID,
            path: String,
            sourceTree: SourceTree = .group,
            name: String? = nil,
            children: [Reference]
        ) {
            precondition(
                Set(children.map({ $0.guid })).count == children.count,
                "multiple group children with the same guid: \(children.map({ $0.guid }))"
            )

            self.children = children

            super.init(guid: guid, path: path, sourceTree: sourceTree, name: name)
        }

        private enum CodingKeys: CodingKey {
            case children, type
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(children, forKey: .children)
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let untypedChildren = try container.decode([TypedObject].self, forKey: .children)
            var childrenContainer = try container.nestedUnkeyedContainer(forKey: .children)

            self.children = try untypedChildren.map { child in
                switch child.type {
                case Group.type:
                    return try childrenContainer.decode(Group.self)
                case FileReference.type:
                    return try childrenContainer.decode(FileReference.self)
                default:
                    throw InternalError("unknown reference type \(child.type ?? "<nil>")")
                }
            }

            try super.init(from: decoder)
        }
    }

    /// Represents a dependency on another target (identified by its PIF GUID).
    public struct TargetDependency: Codable {
        /// Identifier of depended-upon target.
        public var targetGUID: String

        /// The platform filters for this target dependency.
        public var platformFilters: [PlatformFilter]

        public init(targetGUID: String, platformFilters: [PlatformFilter] = [])  {
            self.targetGUID = targetGUID
            self.platformFilters = platformFilters
        }

        private enum CodingKeys: CodingKey {
            case guid, platformFilters
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("\(targetGUID)@\(schemaVersion)", forKey: .guid)

            if !platformFilters.isEmpty {
                try container.encode(platformFilters, forKey: .platformFilters)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let targetGUIDString = try container.decode(String.self, forKey: .guid)
            self.targetGUID = String(targetGUIDString.dropLast("\(schemaVersion)".count + 1))
            platformFilters = try container.decodeIfPresent([PlatformFilter].self, forKey: .platformFilters) ?? []
        }
    }

    public class BaseTarget: TypedObject {
        class override var type: String { "target" }
        public let guid: GUID
        public var name: String
        public var buildConfigurations: [BuildConfiguration]
        public var buildPhases: [BuildPhase]
        public var dependencies: [TargetDependency]
        public var impartedBuildProperties: ImpartedBuildProperties
        var signature: String?

        fileprivate init(
            guid: GUID,
            name: String,
            buildConfigurations: [BuildConfiguration],
            buildPhases: [BuildPhase],
            dependencies: [TargetDependency],
            impartedBuildSettings: PIF.BuildSettings,
            signature: String?
        ) {
            self.guid = guid
            self.name = name
            self.buildConfigurations = buildConfigurations
            self.buildPhases = buildPhases
            self.dependencies = dependencies
            impartedBuildProperties = ImpartedBuildProperties(settings: impartedBuildSettings)
            self.signature = signature
            super.init()
        }

        public required init(from decoder: Decoder) throws {
            throw InternalError("init(from:) has not been implemented")
        }
    }

    public final class AggregateTarget: BaseTarget {
        public init(
            guid: GUID,
            name: String,
            buildConfigurations: [BuildConfiguration],
            buildPhases: [BuildPhase],
            dependencies: [TargetDependency],
            impartedBuildSettings: PIF.BuildSettings
        ) {
            super.init(
                guid: guid,
                name: name,
                buildConfigurations: buildConfigurations,
                buildPhases: buildPhases,
                dependencies: dependencies,
                impartedBuildSettings: impartedBuildSettings,
                signature: nil
            )
        }

        private enum CodingKeys: CodingKey {
            case type, guid, name, buildConfigurations, buildPhases, dependencies, impartedBuildProperties, signature
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: StringKey.self)
            var contents = container.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")
            try contents.encode("aggregate", forKey: .type)
            try contents.encode("\(guid)@\(schemaVersion)", forKey: .guid)
            try contents.encode(name, forKey: .name)
            try contents.encode(buildConfigurations, forKey: .buildConfigurations)
            try contents.encode(buildPhases, forKey: .buildPhases)
            try contents.encode(dependencies, forKey: .dependencies)
            try contents.encode(impartedBuildProperties, forKey: .impartedBuildProperties)

            if encoder.userInfo.keys.contains(.encodeForXCBuild) {
                guard let signature else {
                    throw InternalError("Expected to have \(Swift.type(of: self)) signature when encoding for XCBuild")
                }
                try container.encode(signature, forKey: "signature")
            }
        }

        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: StringKey.self)
            let container = try superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")

            let guidString = try container.decode(GUID.self, forKey: .guid)
            let guid = String(guidString.dropLast("\(schemaVersion)".count + 1))

            let name = try container.decode(String.self, forKey: .name)
            let buildConfigurations = try container.decode([BuildConfiguration].self, forKey: .buildConfigurations)

            let untypedBuildPhases = try container.decode([TypedObject].self, forKey: .buildPhases)
            var buildPhasesContainer = try container.nestedUnkeyedContainer(forKey: .buildPhases)

            let buildPhases: [BuildPhase] = try untypedBuildPhases.map {
                guard let type = $0.type else {
                    throw InternalError("Expected type in build phase \($0)")
                }
                return try BuildPhase.decode(container: &buildPhasesContainer, type: type)
            }

            let dependencies = try container.decode([TargetDependency].self, forKey: .dependencies)
            let impartedBuildProperties = try container.decode(BuildSettings.self, forKey: .impartedBuildProperties)

            super.init(
                guid: guid,
                name: name,
                buildConfigurations: buildConfigurations,
                buildPhases: buildPhases,
                dependencies: dependencies,
                impartedBuildSettings: impartedBuildProperties,
                signature: nil
            )
        }
    }

    /// An Xcode target, representing a single entity to build.
    public final class Target: BaseTarget {
        public enum ProductType: String, Codable {
            case application = "com.apple.product-type.application"
            case staticArchive = "com.apple.product-type.library.static"
            case objectFile = "com.apple.product-type.objfile"
            case dynamicLibrary = "com.apple.product-type.library.dynamic"
            case framework = "com.apple.product-type.framework"
            case executable = "com.apple.product-type.tool"
            case unitTest = "com.apple.product-type.bundle.unit-test"
            case bundle = "com.apple.product-type.bundle"
            case packageProduct = "packageProduct"
        }

        public var productName: String
        public var productType: ProductType

        public init(
            guid: GUID,
            name: String,
            productType: ProductType,
            productName: String,
            buildConfigurations: [BuildConfiguration],
            buildPhases: [BuildPhase],
            dependencies: [TargetDependency],
            impartedBuildSettings: PIF.BuildSettings
        ) {
            self.productType = productType
            self.productName = productName

            super.init(
                guid: guid,
                name: name,
                buildConfigurations: buildConfigurations,
                buildPhases: buildPhases,
                dependencies: dependencies,
                impartedBuildSettings: impartedBuildSettings,
                signature: nil
            )
        }

        private enum CodingKeys: CodingKey {
            case guid, name, dependencies, buildConfigurations, type, frameworksBuildPhase, productTypeIdentifier, productReference, buildRules, buildPhases, impartedBuildProperties, signature
        }

        override public func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: StringKey.self)
            var contents = container.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")
            try contents.encode("\(guid)@\(schemaVersion)", forKey: .guid)
            try contents.encode(name, forKey: .name)
            try contents.encode(dependencies, forKey: .dependencies)
            try contents.encode(buildConfigurations, forKey: .buildConfigurations)

            if encoder.userInfo.keys.contains(.encodeForXCBuild) {
                guard let signature else {
                    throw InternalError("Expected to have \(Swift.type(of: self)) signature when encoding for XCBuild")
                }
                try container.encode(signature, forKey: "signature")
            }

            if productType == .packageProduct {
                try contents.encode("packageProduct", forKey: .type)

                // Add the framework build phase, if present.
                if let phase = buildPhases.first as? PIF.FrameworksBuildPhase {
                    try contents.encode(phase, forKey: .frameworksBuildPhase)
                }
            } else {
                try contents.encode("standard", forKey: .type)
                try contents.encode(productType, forKey: .productTypeIdentifier)

                let productReference = [
                    "type": "file",
                    "guid": "PRODUCTREF-\(guid)",
                    "name": productName,
                ]
                try contents.encode(productReference, forKey: .productReference)

                try contents.encode([String](), forKey: .buildRules)
                try contents.encode(buildPhases, forKey: .buildPhases)
                try contents.encode(impartedBuildProperties, forKey: .impartedBuildProperties)
            }
        }

        public required init(from decoder: Decoder) throws {
            let superContainer = try decoder.container(keyedBy: StringKey.self)
            let container = try superContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: "contents")

            let guidString = try container.decode(GUID.self, forKey: .guid)
            let guid = String(guidString.dropLast("\(schemaVersion)".count + 1))
            let name = try container.decode(String.self, forKey: .name)
            let buildConfigurations = try container.decode([BuildConfiguration].self, forKey: .buildConfigurations)
            let dependencies = try container.decode([TargetDependency].self, forKey: .dependencies)

            let type = try container.decode(String.self, forKey: .type)

            let buildPhases: [BuildPhase]
            let impartedBuildProperties: ImpartedBuildProperties

            if type == "packageProduct" {
                self.productType = .packageProduct
                self.productName = ""
                let fwkBuildPhase = try container.decodeIfPresent(FrameworksBuildPhase.self, forKey: .frameworksBuildPhase)
                buildPhases = fwkBuildPhase.map{ [$0] } ?? []
                impartedBuildProperties = ImpartedBuildProperties(settings: BuildSettings())
            } else if type == "standard" {
                self.productType = try container.decode(ProductType.self, forKey: .productTypeIdentifier)

                let productReference = try container.decode([String: String].self, forKey: .productReference)
                self.productName = productReference["name"]!

                let untypedBuildPhases = try container.decodeIfPresent([TypedObject].self, forKey: .buildPhases) ?? []
                var buildPhasesContainer = try container.nestedUnkeyedContainer(forKey: .buildPhases)

                buildPhases = try untypedBuildPhases.map {
                    guard let type = $0.type else {
                        throw InternalError("Expected type in build phase \($0)")
                    }
                    return try BuildPhase.decode(container: &buildPhasesContainer, type: type)
                }

                impartedBuildProperties = try container.decode(ImpartedBuildProperties.self, forKey: .impartedBuildProperties)
            } else {
                throw InternalError("Unhandled target type \(type)")
            }

            super.init(
                guid: guid,
                name: name,
                buildConfigurations: buildConfigurations,
                buildPhases: buildPhases,
                dependencies: dependencies,
                impartedBuildSettings: impartedBuildProperties.buildSettings,
                signature: nil
            )
        }
    }

    /// Abstract base class for all build phases in a target.
    public class BuildPhase: TypedObject {
        static func decode(container: inout UnkeyedDecodingContainer, type: String) throws -> BuildPhase {
            switch type {
            case HeadersBuildPhase.type:
                return try container.decode(HeadersBuildPhase.self)
            case SourcesBuildPhase.type:
                return try container.decode(SourcesBuildPhase.self)
            case FrameworksBuildPhase.type:
                return try container.decode(FrameworksBuildPhase.self)
            case ResourcesBuildPhase.type:
                return try container.decode(ResourcesBuildPhase.self)
            default:
                throw InternalError("unknown build phase \(type)")
            }
        }

        public let guid: GUID
        public var buildFiles: [BuildFile]

        public init(guid: GUID, buildFiles: [BuildFile]) {
            precondition(!guid.isEmpty)

            self.guid = guid
            self.buildFiles = buildFiles
            super.init()
        }

        private enum CodingKeys: CodingKey {
            case guid, buildFiles
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(guid, forKey: .guid)
            try container.encode(buildFiles, forKey: .buildFiles)
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.guid = try container.decode(GUID.self, forKey: .guid)
            self.buildFiles = try container.decode([BuildFile].self, forKey: .buildFiles)
            try super.init(from: decoder)
        }
    }

    /// A "headers" build phase, i.e. one that copies headers into a directory of the product, after suitable
    /// processing.
    public final class HeadersBuildPhase: BuildPhase {
        override class var type: String { "com.apple.buildphase.headers" }
    }

    /// A "sources" build phase, i.e. one that compiles sources and provides them to be linked into the executable code
    /// of the product.
    public final class SourcesBuildPhase: BuildPhase {
        override class var type: String { "com.apple.buildphase.sources" }
    }

    /// A "frameworks" build phase, i.e. one that links compiled code and libraries into the executable of the product.
    public final class FrameworksBuildPhase: BuildPhase {
        override class var type: String { "com.apple.buildphase.frameworks" }
    }

    public final class ResourcesBuildPhase: BuildPhase {
        override class var type: String { "com.apple.buildphase.resources" }
    }

    /// A build file, representing the membership of either a file or target product reference in a build phase.
    public struct BuildFile: Codable {
        public enum Reference {
            case file(guid: PIF.GUID)
            case target(guid: PIF.GUID)
        }

        public enum HeaderVisibility: String, Codable {
            case `public` = "public"
            case `private` = "private"
        }

        public let guid: GUID
        public var reference: Reference
        public var headerVisibility: HeaderVisibility? = nil
        public var platformFilters: [PlatformFilter]

        public init(guid: GUID, file: FileReference, platformFilters: [PlatformFilter], headerVisibility: HeaderVisibility? = nil) {
            self.guid = guid
            self.reference = .file(guid: file.guid)
            self.platformFilters = platformFilters
            self.headerVisibility = headerVisibility
        }

        public init(guid: GUID, fileGUID: PIF.GUID, platformFilters: [PlatformFilter], headerVisibility: HeaderVisibility? = nil) {
            self.guid = guid
            self.reference = .file(guid: fileGUID)
            self.platformFilters = platformFilters
            self.headerVisibility = headerVisibility
        }

        public init(guid: GUID, target: PIF.BaseTarget, platformFilters: [PlatformFilter], headerVisibility: HeaderVisibility? = nil) {
            self.guid = guid
            self.reference = .target(guid: target.guid)
            self.platformFilters = platformFilters
            self.headerVisibility = headerVisibility
        }

        public init(guid: GUID, targetGUID: PIF.GUID, platformFilters: [PlatformFilter], headerVisibility: HeaderVisibility? = nil) {
            self.guid = guid
            self.reference = .target(guid: targetGUID)
            self.platformFilters = platformFilters
            self.headerVisibility = headerVisibility
        }

        public init(guid: GUID, reference: Reference, platformFilters: [PlatformFilter], headerVisibility: HeaderVisibility? = nil) {
            self.guid = guid
            self.reference = reference
            self.platformFilters = platformFilters
            self.headerVisibility = headerVisibility
        }

        private enum CodingKeys: CodingKey {
            case guid, platformFilters, fileReference, targetReference, headerVisibility
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(guid, forKey: .guid)
            try container.encode(platformFilters, forKey: .platformFilters)
            try container.encodeIfPresent(headerVisibility, forKey: .headerVisibility)

            switch self.reference {
            case .file(let fileGUID):
                try container.encode(fileGUID, forKey: .fileReference)
            case .target(let targetGUID):
                try container.encode("\(targetGUID)@\(schemaVersion)", forKey: .targetReference)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guid = try container.decode(GUID.self, forKey: .guid)
            platformFilters = try container.decode([PlatformFilter].self, forKey: .platformFilters)
            headerVisibility = try container.decodeIfPresent(HeaderVisibility.self, forKey: .headerVisibility)

            if container.allKeys.contains(.fileReference) {
                reference = try .file(guid: container.decode(GUID.self, forKey: .fileReference))
            } else if container.allKeys.contains(.targetReference) {
                let targetGUIDString = try container.decode(GUID.self, forKey: .targetReference)
                let targetGUID = String(targetGUIDString.dropLast("\(schemaVersion)".count + 1))
                reference = .target(guid: targetGUID)
            } else {
                throw InternalError("Expected \(CodingKeys.fileReference) or \(CodingKeys.targetReference) in the keys")
            }
        }
    }

    /// Represents a generic platform filter.
    public struct PlatformFilter: Codable, Equatable {
        /// The name of the platform (`LC_BUILD_VERSION`).
        ///
        /// Example: macos, ios, watchos, tvos.
        public var platform: String

        /// The name of the environment (`LC_BUILD_VERSION`)
        ///
        /// Example: simulator, maccatalyst.
        public var environment: String

        public init(platform: String, environment: String = "") {
            self.platform = platform
            self.environment = environment
        }
    }

    /// A build configuration, which is a named collection of build settings.
    public struct BuildConfiguration: Codable {
        public let guid: GUID
        public var name: String
        public var buildSettings: BuildSettings
        public let impartedBuildProperties: ImpartedBuildProperties

        public init(guid: GUID, name: String, buildSettings: BuildSettings, impartedBuildProperties: ImpartedBuildProperties = ImpartedBuildProperties(settings: BuildSettings())) {
            precondition(!guid.isEmpty)
            precondition(!name.isEmpty)

            self.guid = guid
            self.name = name
            self.buildSettings = buildSettings
            self.impartedBuildProperties = impartedBuildProperties
        }
    }

    public struct ImpartedBuildProperties: Codable {
        public var buildSettings: BuildSettings

        public init(settings: BuildSettings) {
            self.buildSettings = settings
        }
    }

    /// A set of build settings, which is represented as a struct of optional build settings. This is not optimally
    /// efficient, but it is great for code completion and type-checking.
    public struct BuildSettings: Codable {
        public enum SingleValueSetting: String, Codable {
            case APPLICATION_EXTENSION_API_ONLY
            case BUILT_PRODUCTS_DIR
            case CLANG_CXX_LANGUAGE_STANDARD
            case CLANG_ENABLE_MODULES
            case CLANG_ENABLE_OBJC_ARC
            case CODE_SIGNING_REQUIRED
            case CODE_SIGN_IDENTITY
            case COMBINE_HIDPI_IMAGES
            case COPY_PHASE_STRIP
            case DEBUG_INFORMATION_FORMAT
            case DEFINES_MODULE
            case DRIVERKIT_DEPLOYMENT_TARGET
            case DYLIB_INSTALL_NAME_BASE
            case EMBEDDED_CONTENT_CONTAINS_SWIFT
            case ENABLE_NS_ASSERTIONS
            case ENABLE_TESTABILITY
            case ENABLE_TESTING_SEARCH_PATHS
            case ENTITLEMENTS_REQUIRED
            case EXECUTABLE_PREFIX
            case GENERATE_INFOPLIST_FILE
            case GCC_C_LANGUAGE_STANDARD
            case GCC_OPTIMIZATION_LEVEL
            case GENERATE_MASTER_OBJECT_FILE
            case INFOPLIST_FILE
            case IPHONEOS_DEPLOYMENT_TARGET
            case KEEP_PRIVATE_EXTERNS
            case CLANG_COVERAGE_MAPPING_LINKER_ARGS
            case MACH_O_TYPE
            case MACOSX_DEPLOYMENT_TARGET
            case MODULEMAP_FILE
            case MODULEMAP_FILE_CONTENTS
            case MODULEMAP_PATH
            case MODULE_CACHE_DIR
            case ONLY_ACTIVE_ARCH
            case PACKAGE_RESOURCE_BUNDLE_NAME
            case PACKAGE_RESOURCE_TARGET_KIND
            case PRODUCT_BUNDLE_IDENTIFIER
            case PRODUCT_MODULE_NAME
            case PRODUCT_NAME
            case PROJECT_NAME
            case SDKROOT
            case SDK_VARIANT
            case SKIP_INSTALL
            case INSTALL_PATH
            case SUPPORTS_MACCATALYST
            case SWIFT_SERIALIZE_DEBUGGING_OPTIONS
            case SWIFT_INSTALL_OBJC_HEADER
            case SWIFT_OBJC_INTERFACE_HEADER_NAME
            case SWIFT_OBJC_INTERFACE_HEADER_DIR
            case SWIFT_OPTIMIZATION_LEVEL
            case SWIFT_VERSION
            case TARGET_NAME
            case TARGET_BUILD_DIR
            case TVOS_DEPLOYMENT_TARGET
            case USE_HEADERMAP
            case USES_SWIFTPM_UNSAFE_FLAGS
            case WATCHOS_DEPLOYMENT_TARGET
            case XROS_DEPLOYMENT_TARGET
            case MARKETING_VERSION
            case CURRENT_PROJECT_VERSION
            case SWIFT_EMIT_MODULE_INTERFACE
            case GENERATE_RESOURCE_ACCESSORS
        }

        public enum MultipleValueSetting: String, Codable {
            case EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES
            case FRAMEWORK_SEARCH_PATHS
            case GCC_PREPROCESSOR_DEFINITIONS
            case HEADER_SEARCH_PATHS
            case LD_RUNPATH_SEARCH_PATHS
            case LIBRARY_SEARCH_PATHS
            case OTHER_CFLAGS
            case OTHER_CPLUSPLUSFLAGS
            case OTHER_LDFLAGS
            case OTHER_LDRFLAGS
            case OTHER_SWIFT_FLAGS
            case PRELINK_FLAGS
            case SPECIALIZATION_SDK_OPTIONS
            case SUPPORTED_PLATFORMS
            case SWIFT_ACTIVE_COMPILATION_CONDITIONS
            case SWIFT_MODULE_ALIASES
        }

        public enum Platform: String, CaseIterable, Codable {
            case macOS = "macos"
            case macCatalyst = "maccatalyst"
            case iOS = "ios"
            case tvOS = "tvos"
            case watchOS = "watchos"
            case driverKit = "driverkit"
            case linux

            public var packageModelPlatform: PackageModel.Platform {
                switch self {
                case .macOS: return .macOS
                case .macCatalyst: return .macCatalyst
                case .iOS: return .iOS
                case .tvOS: return .tvOS
                case .watchOS: return .watchOS
                case .driverKit: return .driverKit
                case .linux: return .linux
                }
            }

            public var conditions: [String] {
                let filters = [PackageCondition(platforms: [packageModelPlatform])].toPlatformFilters().map { filter in
                    if filter.environment.isEmpty {
                        return filter.platform
                    } else {
                        return "\(filter.platform)-\(filter.environment)"
                    }
                }.sorted()
                return ["__platform_filter=\(filters.joined(separator: ";"))"]
            }
        }

        public private(set) var platformSpecificSingleValueSettings = OrderedDictionary<Platform, OrderedDictionary<SingleValueSetting, String>>()
        public private(set) var platformSpecificMultipleValueSettings = OrderedDictionary<Platform, OrderedDictionary<MultipleValueSetting, [String]>>()
        public private(set) var singleValueSettings: OrderedDictionary<SingleValueSetting, String> = [:]
        public private(set) var multipleValueSettings: OrderedDictionary<MultipleValueSetting, [String]> = [:]

        public subscript(_ setting: SingleValueSetting) -> String? {
            get { singleValueSettings[setting] }
            set { singleValueSettings[setting] = newValue }
        }

        public subscript(_ setting: SingleValueSetting, for platform: Platform) -> String? {
            get { platformSpecificSingleValueSettings[platform]?[setting] }
            set { platformSpecificSingleValueSettings[platform, default: [:]][setting] = newValue }
        }

        public subscript(_ setting: SingleValueSetting, default defaultValue: @autoclosure () -> String) -> String {
            get { singleValueSettings[setting, default: defaultValue()] }
            set { singleValueSettings[setting] = newValue }
        }

        public subscript(_ setting: MultipleValueSetting) -> [String]? {
            get { multipleValueSettings[setting] }
            set { multipleValueSettings[setting] = newValue }
        }

        public subscript(_ setting: MultipleValueSetting, for platform: Platform) -> [String]? {
            get { platformSpecificMultipleValueSettings[platform]?[setting] }
            set { platformSpecificMultipleValueSettings[platform, default: [:]][setting] = newValue }
        }

        public subscript(
            _ setting: MultipleValueSetting,
            default defaultValue: @autoclosure () -> [String]
        ) -> [String] {
            get { multipleValueSettings[setting, default: defaultValue()] }
            set { multipleValueSettings[setting] = newValue }
        }

        public subscript(
            _ setting: MultipleValueSetting,
            for platform: Platform,
            default defaultValue: @autoclosure () -> [String]
        ) -> [String] {
            get { platformSpecificMultipleValueSettings[platform, default: [:]][setting, default: defaultValue()] }
            set { platformSpecificMultipleValueSettings[platform, default: [:]][setting] = newValue }
        }

        public init() {
        }

        private enum CodingKeys: CodingKey {
            case platformSpecificSingleValueSettings, platformSpecificMultipleValueSettings, singleValueSettings, multipleValueSettings
        }

        public func encode(to encoder: Encoder) throws {
            if encoder.userInfo.keys.contains(.encodeForXCBuild) {
                return try encodeForXCBuild(to: encoder)
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(platformSpecificSingleValueSettings, forKey: .platformSpecificSingleValueSettings)
            try container.encode(platformSpecificMultipleValueSettings, forKey: .platformSpecificMultipleValueSettings)
            try container.encode(singleValueSettings, forKey: .singleValueSettings)
            try container.encode(multipleValueSettings, forKey: .multipleValueSettings)
        }

        private func encodeForXCBuild(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: StringKey.self)

            for (key, value) in singleValueSettings {
                try container.encode(value, forKey: StringKey(key.rawValue))
            }

            for (key, value) in multipleValueSettings {
                try container.encode(value, forKey: StringKey(key.rawValue))
            }

            for (platform, values) in platformSpecificSingleValueSettings {
                for condition in platform.conditions {
                    for (key, value) in values {
                        try container.encode(value, forKey: "\(key.rawValue)[\(condition)]")
                    }
                }
            }

            for (platform, values) in platformSpecificMultipleValueSettings {
                for condition in platform.conditions {
                    for (key, value) in values {
                        try container.encode(value, forKey: "\(key.rawValue)[\(condition)]")
                    }
                }
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            platformSpecificSingleValueSettings = try container.decodeIfPresent(OrderedDictionary<Platform, OrderedDictionary<SingleValueSetting, String>>.self, forKey: .platformSpecificSingleValueSettings) ?? .init()
            platformSpecificMultipleValueSettings = try container.decodeIfPresent(OrderedDictionary<Platform, OrderedDictionary<MultipleValueSetting, [String]>>.self, forKey: .platformSpecificMultipleValueSettings) ?? .init()
            singleValueSettings = try container.decodeIfPresent(OrderedDictionary<SingleValueSetting, String>.self, forKey: .singleValueSettings) ?? [:]
            multipleValueSettings = try container.decodeIfPresent(OrderedDictionary<MultipleValueSetting, [String]>.self, forKey: .multipleValueSettings) ?? [:]
        }
    }
}

/// Represents a filetype recognized by the Xcode build system.
public struct XCBuildFileType: CaseIterable {
    public static let xcassets: XCBuildFileType = XCBuildFileType(
        fileType: "xcassets",
        fileTypeIdentifier: "folder.abstractassetcatalog"
    )

    public static let xcdatamodeld: XCBuildFileType = XCBuildFileType(
        fileType: "xcdatamodeld",
        fileTypeIdentifier: "wrapper.xcdatamodeld"
    )

    public static let xcdatamodel: XCBuildFileType = XCBuildFileType(
        fileType: "xcdatamodel",
        fileTypeIdentifier: "wrapper.xcdatamodel"
    )

    public static let xcmappingmodel: XCBuildFileType = XCBuildFileType(
        fileType: "xcmappingmodel",
        fileTypeIdentifier: "wrapper.xcmappingmodel"
    )

    public static let allCases: [XCBuildFileType] = [
        .xcdatamodeld,
        .xcdatamodel,
        .xcmappingmodel,
    ]

    public let fileTypes: Set<String>
    public let fileTypeIdentifier: String

    private init(fileTypes: Set<String>, fileTypeIdentifier: String) {
        self.fileTypes = fileTypes
        self.fileTypeIdentifier = fileTypeIdentifier
    }

    private init(fileType: String, fileTypeIdentifier: String) {
        self.init(fileTypes: [fileType], fileTypeIdentifier: fileTypeIdentifier)
    }
}

struct StringKey: CodingKey, ExpressibleByStringInterpolation {
    var stringValue: String
    var intValue: Int?

    init(stringLiteral stringValue: String) {
        self.stringValue = stringValue
    }

    init(stringValue value: String) {
        self.stringValue = value
    }

    init(_ value: String) {
        self.stringValue = value
    }

    init?(intValue: Int) {
        assertionFailure("does not support integer keys")
        return nil
    }
}

extension PIF.FileReference {
    fileprivate static func fileTypeIdentifier(forPath path: String) -> String {
        let pathExtension: String?
        if let path = try? AbsolutePath(validating: path) {
            pathExtension = path.extension
        } else if let path = try? RelativePath(validating: path) {
            pathExtension = path.extension
        } else {
            pathExtension = nil
        }

        switch pathExtension {
        case "a":
            return "archive.ar"
        case "s", "S":
            return "sourcecode.asm"
        case "c":
            return "sourcecode.c.c"
        case "cl":
            return "sourcecode.opencl"
        case "cpp", "cp", "cxx", "cc", "c++", "C", "tcc":
            return "sourcecode.cpp.cpp"
        case "d":
            return "sourcecode.dtrace"
        case "defs", "mig":
            return "sourcecode.mig"
        case "m":
            return "sourcecode.c.objc"
        case "mm", "M":
            return "sourcecode.cpp.objcpp"
        case "metal":
            return "sourcecode.metal"
        case "l", "lm", "lmm", "lpp", "lp", "lxx":
            return "sourcecode.lex"
        case "swift":
            return "sourcecode.swift"
        case "y", "ym", "ymm", "ypp", "yp", "yxx":
            return "sourcecode.yacc"

        case "xcassets":
            return "folder.assetcatalog"
        case "xcstrings":
            return "text.json.xcstrings"
        case "storyboard":
            return "file.storyboard"
        case "xib":
            return "file.xib"

        case "xcframework":
            return "wrapper.xcframework"

        default:
            return pathExtension.flatMap({ pathExtension in
                XCBuildFileType.allCases.first(where:{ $0.fileTypes.contains(pathExtension) })
            })?.fileTypeIdentifier ?? "file"
        }
    }
}

extension CodingUserInfoKey {
    public static let encodingPIFSignature: CodingUserInfoKey = CodingUserInfoKey(rawValue: "encodingPIFSignature")!

    /// Perform the encoding for XCBuild consumption.
    public static let encodeForXCBuild: CodingUserInfoKey = CodingUserInfoKey(rawValue: "encodeForXCBuild")!
}

private struct UntypedTarget: Decodable {
    struct TargetContents: Decodable {
        let type: String
    }
    let contents: TargetContents
}

protocol PIFSignableObject: AnyObject {
    var signature: String? { get set }
}
extension PIF.Workspace: PIFSignableObject {}
extension PIF.Project: PIFSignableObject {}
extension PIF.BaseTarget: PIFSignableObject {}

extension PIF {
    /// Add signature to workspace and its subobjects.
    public static func sign(_ workspace: PIF.Workspace) throws {
        let encoder = JSONEncoder.makeWithDefaults()

        func sign<T: PIFSignableObject & Encodable>(_ obj: T) throws {
            let signatureContent = try encoder.encode(obj)
            let bytes = ByteString(signatureContent)
            obj.signature = bytes.sha256Checksum
        }

        let projects = workspace.projects
        try projects.flatMap{ $0.targets }.forEach(sign)
        try projects.forEach(sign)
        try sign(workspace)
    }
}
