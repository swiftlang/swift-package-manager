/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

/// The Project Interchange Format (PIF) is a structured representation of the
/// project model created by clients (Xcode/SwiftPM) to send to XCBuild.
///
/// The PIF is a representation of the project model describing the static
/// objects which contribute to building products from the project, independent
/// of "how" the user has chosen to build those products in any particular
/// build. This information can be cached by XCBuild between builds (even
/// between builds which use different schemes or configurations), and can be
/// incrementally updated by clients when something changes.

/// The top-level PIF object.
public enum PIF {
    public struct TopLevelObject {
        let workspace: PIF.Workspace
    }

    public final class Workspace {
        public let signature: String
        public let guid: String
        public var path: String
        public var name: String
        public var projects: [Project]

        init(guid: String, path: String, name: String) {
            self.guid = guid
            self.path = path
            self.name = name
            self.projects = []
            self.signature = UUID().uuidString  // temporary
        }

        @discardableResult
        public func addProject(
            id: String,
            path: String,
            projectDir: String,
            name: String
        ) -> Project {
            precondition(!name.isEmpty)
            let project = Project(id: id, path: path, projectDir: projectDir, name: name)
            projects.append(project)
            return project
        }
    }

    /// A PIF project, consisting of a tree of groups and file references, a list of targets, and some additional
    /// information.
    public final class Project {
        public let id: String
        public var signature: String?
        public let name: String
        public var path: String
        public let mainGroup: Group
        public var buildConfigs: [BuildConfig]
        public var productGroup: Group?
        public var projectDir: String
        public var targets: [BaseTarget]

        public init(id: String, path: String, projectDir: String, name: String) {
            precondition(!id.isEmpty)
            precondition(!path.isEmpty)
            precondition(!projectDir.isEmpty)
            self.id = id
            self.name = name
            self.path = path
            self.mainGroup = Group(id: "\(id)::MAINGROUP", path: "")
            self.buildConfigs = []
            self.productGroup = nil
            self.projectDir = projectDir
            self.targets = []
            self.signature = UUID().uuidString  // temporary
        }

        private var nextTargetId: String {
            return "\(self.id)::TARGET_\(targets.count)"
        }

        /// Creates and adds a new empty target, i.e. one that does not initially have any build phases. If provided,
        /// the ID must be non-empty and unique within the PIF workspace; if not provided, an arbitrary
        /// guaranteed-to-be-unique identifier will be assigned. The name must not be empty and must not be equal to the
        /// name of any existing target in the project.
        @discardableResult
        public func addTarget(
            id: String? = nil,
            productType: Target.ProductType,
            name: String,
            productName: String
        ) -> Target {
            let id = id ?? nextTargetId
            precondition(!id.isEmpty)
            precondition(!targets.contains(where: { $0.id == id }))
            precondition(!name.isEmpty)
            let target = Target(id: id, productType: productType, name: name, productName: productName)
            targets.append(target)
            return target
        }

        @discardableResult
        public func addAggregateTarget(id: String? = nil, name: String) -> AggregateTarget {
            let id = id ?? nextTargetId
            precondition(!id.isEmpty)
            precondition(!targets.contains(where: { $0.id == id }))
            precondition(!name.isEmpty)
            let target = AggregateTarget(id: id, name: name)
            targets.append(target)
            return target
        }

        /// Creates and adds a new empty build configuration, i.e. one that does not initially have any build settings.
        /// The name must not be empty and must not be equal to the name of any existing build configuration in the
        /// project.
        @discardableResult
        public func addBuildConfig(name: String, settings: BuildSettings = BuildSettings()) -> BuildConfig {
            precondition(!name.isEmpty)
            precondition(!buildConfigs.contains(where: { $0.name == name }))
            let id = "\(self.id)::BUILDCONFIG_\(buildConfigs.count)"
            let buildConfig = BuildConfig(id: id, name: name, settings: settings)
            buildConfigs.append(buildConfig)
            return buildConfig
        }
    }

    /// Abstract base class for all items in the group hierarhcy.
    public class Reference: Encodable {

        public let id: String

        /// Relative path of the reference.  It is usually a literal, but may in fact contain build settings.
        public var path: String

        /// Determines the base path for the reference's relative path.
        public var pathBase: RefPathBase

        /// Name of the reference, if different from the last path component (if not set, the last path component will
        /// be used as the name).
        public var name: String? = nil

        /// Determines the base path for a reference's relative path.
        public enum RefPathBase: String {
            /// Indicates that the path is relative to the source root (i.e. the "project directory").
            case projectDir = "SOURCE_ROOT"

            /// Indicates that the path is relative to the path of the parent group.
            case groupDir = "<group>"

            /// Indicates that the path is relative to the effective build directory (which varies depending on active
            /// scheme, active run destination, or even an overridden build setting.
            case buildDir = "BUILT_PRODUCTS_DIR"

            /// Indicates that the path is an absolute path.
            case absolute = "<absolute>"

            /// The string form, suitable for use in the PIF representation.
            public var asString: String { return rawValue }
        }

        fileprivate init(
            id: String,
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil
        ) {
            self.id = id
            self.path = path
            self.pathBase = pathBase
            self.name = name
        }

        public func encode(to encoder: Encoder) throws {
            fatalError("subclass responsibility")
        }
    }

    /// A reference to a file system entity (a file, folder, etc).
    public final class FileReference: Reference {
        public var fileType: String?

        public init(
            id: String,
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil,
            fileType: String? = nil
        ) {
            super.init(id: id, path: path, pathBase: pathBase, name: name)
            self.fileType = fileType
        }

        override public func encode(to encoder: Encoder) throws {
            try _encode(to: encoder)
        }
    }

    /// A group that can contain References (FileReferences and other Groups). The resolved path of a group is used as
    /// the base path for any child references whose source tree type is GroupRelative.
    public final class Group: Reference {
        public var subitems: [Reference] = []

        private var nextRefId: String {
            return "\(self.id)::REF_\(subitems.count)"
        }

        /// Creates and appends a new Group to the list of subitems.  The new group is returned so that it can be
        /// configured.
        public func addGroup(path: String, pathBase: RefPathBase = .groupDir, name: String? = nil) -> Group {
            let group = Group(id: nextRefId, path: path, pathBase: pathBase, name: name)
            subitems.append(group)
            return group
        }

        /// Creates and appends a new FileReference to the list of subitems.
        public func addFileReference(
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil,
            fileType: String? = nil
        ) -> FileReference {
            let fref = FileReference(
                id: nextRefId,
                path: path,
                pathBase: pathBase,
                name: name,
                fileType: fileType
            )
            subitems.append(fref)
            return fref
        }

        override public func encode(to encoder: Encoder) throws {
            try _encode(to: encoder)
        }
    }

    public class BaseTarget: Encodable {
        public func encode(to encoder: Encoder) throws {
            fatalError("subclass responsibility")
        }

        public let id: String
        public var signature: String?
        public var name: String
        public var buildConfigs: [BuildConfig]
        public var impartedBuildProperties: ImpartedBuildProperties
        public var buildPhases: [BuildPhase]
        public var dependencies: [TargetDependency]

        fileprivate init(id: String, name: String) {
            self.id = id
            self.name = name
            self.buildConfigs = []
            self.impartedBuildProperties = ImpartedBuildProperties(settings: BuildSettings())
            self.buildPhases = []
            self.dependencies = []
            self.signature = UUID().uuidString
        }

        public func setImpartedBuildSettings(_ settings: BuildSettings) {
            impartedBuildProperties = ImpartedBuildProperties(settings: settings)
        }

        /// Creates and adds a new empty build configuration, i.e. one that does not initially have any build settings.
        /// The name must not be empty and must not be equal to the name of any existing build configuration in the
        /// target.
        @discardableResult
        public func addBuildConfig(
            name: String,
            settings: BuildSettings = BuildSettings()
        ) -> BuildConfig {
            precondition(!name.isEmpty)
            precondition(!buildConfigs.contains(where: { $0.name == name }))
            let id = "\(self.id)::BUILDCONFIG_\(buildConfigs.count)"
            let buildConfig = BuildConfig(id: id, name: name, settings: settings)
            buildConfigs.append(buildConfig)
            return buildConfig
        }

        /// Represents a dependency on another target (identified by its PIF ID).
        public struct TargetDependency {
            /// Identifier of depended-upon target.
            public let targetId: String
        }
    }

    public final class AggregateTarget: BaseTarget {
        override public func encode(to encoder: Encoder) throws {
            try _encode(to: encoder)
        }
    }

    /// An Xcode target, representing a single entity to build.
    public final class Target: BaseTarget {
        public enum ProductType: String {
            case application = "com.apple.product-type.application"
            case staticArchive = "com.apple.product-type.library.static"
            case objectFile = "com.apple.product-type.objfile"
            case dynamicLibrary = "com.apple.product-type.library.dynamic"
            case framework = "com.apple.product-type.framework"
            case executable = "com.apple.product-type.tool"
            case unitTest = "com.apple.product-type.bundle.unit-test"
            case bundle = "com.apple.product-type.bundle"
            case packageProduct = "packageProduct"
            public var asString: String { return rawValue }
        }

        public var productName: String
        public var productType: ProductType
        public var productReference: FileReference?

        public init(id: String, productType: ProductType, name: String, productName: String) {
            self.productType = productType
            self.productName = productName
            super.init(id: id, name: name)
        }

        override public func encode(to encoder: Encoder) throws {
            try _encode(to: encoder)
        }

        private var nextBuildPhaseId: String {
            return "\(self.id)::BUILDPHASE_\(buildPhases.count)"
        }

        /// Adds a "headers" build phase, i.e. one that copies headers into a directory of the product, after suitable
        /// processing.
        @discardableResult
        public func addHeadersBuildPhase() -> HeadersBuildPhase {
            let phase = HeadersBuildPhase(id: nextBuildPhaseId)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "sources" build phase, i.e. one that compiles sources and provides them to be linked into the
        /// executable code of the product.
        @discardableResult
        public func addSourcesBuildPhase() -> SourcesBuildPhase {
            let phase = SourcesBuildPhase(id: nextBuildPhaseId)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "frameworks" build phase, i.e. one that links compiled code and libraries into the executable of the
        /// product.
        @discardableResult
        public func addFrameworksBuildPhase() -> FrameworksBuildPhase {
            let phase = FrameworksBuildPhase(id: nextBuildPhaseId)
            buildPhases.append(phase)
            return phase
        }

        @discardableResult
        public func addCopyBundleResourcesBuildPhase() -> CopyBundleResourcesBuildPhase {
            let phase = CopyBundleResourcesBuildPhase(id: nextBuildPhaseId)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a dependency on another target. It is the caller's responsibility to avoid creating dependency cycles.
        /// A dependency of one target on another ensures that the other target is built first. If `linkProduct` is
        /// true, the receiver will also be configured to link against the product produced by the other target (this
        /// presumes that the product type is one that can be linked against).
        public func addDependency(on targetId: String, linkProduct: Bool) {
            dependencies.append(TargetDependency(targetId: targetId))
            if linkProduct {
                let frameworksPhase = buildPhases.first(where: { $0 is FrameworksBuildPhase })
                    ?? addFrameworksBuildPhase()
                frameworksPhase.addBuildFile(productOf: targetId)
            }
        }

        /// Convenience function to add a file reference to the Headers build phase, after creating it if needed.
        @discardableResult
        public func addHeaderFile(ref: FileReference) -> BuildFile {
            let headerPhase = buildPhases.first(where: { $0 is HeadersBuildPhase })
                ?? addHeadersBuildPhase()
            return headerPhase.addBuildFile(fileRef: ref)
        }

        /// Convenience function to add a file reference to the Sources build phase, after creating it if needed.
        @discardableResult
        public func addSourceFile(ref: FileReference) -> BuildFile {
            let sourcesPhase = buildPhases.first(where: { $0 is SourcesBuildPhase })
                ?? addSourcesBuildPhase()
            return sourcesPhase.addBuildFile(fileRef: ref)
        }

        /// Convenience function to add a file reference to the Frameworks build phase, after creating it if needed.
        @discardableResult
        public func addLibrary(ref: FileReference) -> BuildFile {
            let frameworksPhase = buildPhases.first(where: { $0 is FrameworksBuildPhase })
                ?? addFrameworksBuildPhase()
            return frameworksPhase.addBuildFile(fileRef: ref)
        }

        @discardableResult
        public func addResourceFile(ref: FileReference) -> BuildFile {
            let resourcesPhase = buildPhases.first(where: { $0 is CopyBundleResourcesBuildPhase })
                ?? addCopyBundleResourcesBuildPhase()
            return resourcesPhase.addBuildFile(fileRef: ref)
        }
    }

    /// Abstract base class for all build phases in a target.
    public class BuildPhase {
        class var type: String {
            fatalError("Subclass should implement")
        }

        public let id: String
        public var files: [BuildFile]

        fileprivate init(id: String) {
            self.id = id
            self.files = []
        }

        private var nextBuildFileId: String {
            return "\(self.id)::\(files.count)"
        }

        /// Adds a new build file that refers to `fileRef`.
        @discardableResult
        public func addBuildFile(fileRef: FileReference) -> BuildFile {
            let buildFile = BuildFile(id: nextBuildFileId, reference: fileRef)
            files.append(buildFile)
            return buildFile
        }

        /// Adds a new build file that refers to the product of the target with ID `targetId`.
        @discardableResult
        public func addBuildFile(productOf targetId: String) -> BuildFile {
            let buildFile = BuildFile(id: nextBuildFileId, targetId: targetId)
            files.append(buildFile)
            return buildFile
        }
    }

    /// A "headers" build phase, i.e. one that copies headers into a directory of the product, after suitable
    /// processing.
    public final class HeadersBuildPhase: BuildPhase {
        override class var type: String {
            "com.apple.buildphase.headers"
        }

        public override init(id: String) {
            super.init(id: id)
        }
    }

    /// A "sources" build phase, i.e. one that compiles sources and provides them to be linked into the executable code
    /// of the product.
    public final class SourcesBuildPhase: BuildPhase {
        override class var type: String {
            "com.apple.buildphase.sources"
        }

        public override init(id: String) {
            super.init(id: id)
        }
    }

    /// A "frameworks" build phase, i.e. one that links compiled code and libraries into the executable of the product.
    public final class FrameworksBuildPhase: BuildPhase {
        override class var type: String {
            "com.apple.buildphase.frameworks"
        }

        public override init(id: String) {
            super.init(id: id)
        }
    }

    public final class CopyBundleResourcesBuildPhase: BuildPhase {
        override class var type: String {
            "com.apple.buildphase.resources"
        }

        public override init(id: String) {
            super.init(id: id)
        }
    }

    /// A build file, representing the membership of either a file or target product reference in a build phase.
    public final class BuildFile {
        public enum Ref {
            case reference(id: String)
            case targetProduct(id: String)
        }

        public enum HeaderVisibility: String {
            case `public` = "public"
            case `private` = "private"
        }

        public let id: String
        public let ref: Ref
        public var headerVisibility: HeaderVisibility? = nil

        public init(id: String, reference: FileReference) {
            self.id = id
            self.ref = .reference(id: reference.id)
        }

        public init(id: String, targetId: String) {
            self.id = id
            self.ref = .targetProduct(id: targetId)
        }
    }

    /// A build configuration, which is a named collection of build settings.
    public final class BuildConfig {
        public let id: String
        public let name: String
        public let settings: BuildSettings

        public init(id: String, name: String, settings: BuildSettings) {
            precondition(!name.isEmpty)
            self.id = id
            self.name = name
            self.settings = settings
        }
    }

    public final class ImpartedBuildProperties {
        public let settings: BuildSettings

        public init(settings: BuildSettings) {
            self.settings = settings
        }
    }

    /// A set of build settings, which is represented as a struct of optional build settings. This is not optimally
    /// efficient, but it is great for code completion and type-checking.
    public struct BuildSettings {
        public enum Declaration: String, CaseIterable {
            case GCC_PREPROCESSOR_DEFINITIONS
            case FRAMEWORK_SEARCH_PATHS
            case HEADER_SEARCH_PATHS
            case OTHER_CFLAGS
            case OTHER_CPLUSPLUSFLAGS
            case OTHER_LDFLAGS
            case OTHER_SWIFT_FLAGS
            case SWIFT_ACTIVE_COMPILATION_CONDITIONS
        }

        public enum Platform: CaseIterable {
            case macOS
            case iOS
            case tvOS
            case watchOS

            public var asConditionStrings: [String] {
                switch self {
                case .macOS: return ["sdk=macosx*"]
                case .iOS: return ["sdk=iphonesimulator*", "sdk=iphoneos*"]
                case .tvOS: return ["sdk=appletvsimulator*", "sdk=appletvos*"]
                case .watchOS: return ["sdk=watchsimulator*", "sdk=watchos*"]
                }
            }
        }

        // Note: although some of these build settings sound like booleans, they are all either strings or arrays of
        // strings, because even a boolean may be a macro reference expression.
        public var APPLICATION_EXTENSION_API_ONLY: String?
        public var BUILT_PRODUCTS_DIR: String?
        public var CLANG_CXX_LANGUAGE_STANDARD: String?
        public var CLANG_ENABLE_MODULES: String?
        public var CLANG_ENABLE_OBJC_ARC: String?
        public var CODE_SIGNING_REQUIRED: String?
        public var CODE_SIGN_IDENTITY: String?
        public var COMBINE_HIDPI_IMAGES: String?
        public var COPY_PHASE_STRIP: String?
        public var DEBUG_INFORMATION_FORMAT: String?
        public var DEFINES_MODULE: String?
        public var DYLIB_INSTALL_NAME_BASE: String?
        public var EMBEDDED_CONTENT_CONTAINS_SWIFT: String?
        public var ENABLE_NS_ASSERTIONS: String?
        public var ENABLE_TESTABILITY: String?
        public var ENABLE_TESTING_SEARCH_PATHS: String?
        public var ENTITLEMENTS_REQUIRED: String?
        public var EMBED_PACKAGE_RESOURCE_BUNDLE_NAMES: [String]?
        public var EXECUTABLE_NAME: String?
        public var FRAMEWORK_SEARCH_PATHS: [String]?
        public var GENERATE_INFOPLIST_FILE: String?
        public var GCC_C_LANGUAGE_STANDARD: String?
        public var GCC_OPTIMIZATION_LEVEL: String?
        public var GCC_PREPROCESSOR_DEFINITIONS: [String]?
        public var GENERATE_MASTER_OBJECT_FILE: String?
        public var HEADER_SEARCH_PATHS: [String]?
        public var INFOPLIST_FILE: String?
        public var IPHONEOS_DEPLOYMENT_TARGET: String?
        public var KEEP_PRIVATE_EXTERNS: String?
        public var LD_RUNPATH_SEARCH_PATHS: [String]?
        public var LIBRARY_SEARCH_PATHS: [String]?
        public var CLANG_COVERAGE_MAPPING_LINKER_ARGS: String?
        public var MACH_O_TYPE: String?
        public var MACOSX_DEPLOYMENT_TARGET: String?
        public var MODULEMAP_FILE_CONTENTS: String?
        public var MODULEMAP_PATH: String?
        public var MODULEMAP_FILE: String?
        public var ONLY_ACTIVE_ARCH: String?
        public var OTHER_CFLAGS: [String]?
        public var OTHER_CPLUSPLUSFLAGS: [String]?
        public var OTHER_LDFLAGS: [String]?
        public var OTHER_LDRFLAGS: [String]?
        public var OTHER_SWIFT_FLAGS: [String]?
        public var PACKAGE_RESOURCE_BUNDLE_NAME: String?
        public var PACKAGE_RESOURCE_TARGET_KIND: String?
        public var PRELINK_FLAGS: [String]?
        public var PRODUCT_BUNDLE_IDENTIFIER: String?
        public var PRODUCT_MODULE_NAME: String?
        public var PRODUCT_NAME: String?
        public var PROJECT_NAME: String?
        public var SDKROOT: String?
        public var SDK_VARIANT: String?
        public var SKIP_INSTALL: String?
        public var INSTALL_PATH: String?
        public var SUPPORTED_PLATFORMS: [String]?
        public var SUPPORTS_MACCATALYST: String?
        public var SWIFT_ACTIVE_COMPILATION_CONDITIONS: [String]?
        public var SWIFT_FORCE_STATIC_LINK_STDLIB: String?
        public var SWIFT_FORCE_DYNAMIC_LINK_STDLIB: String?
        public var SWIFT_INSTALL_OBJC_HEADER: String?
        public var SWIFT_OBJC_INTERFACE_HEADER_NAME: String?
        public var SWIFT_OBJC_INTERFACE_HEADER_DIR: String?
        public var SWIFT_OPTIMIZATION_LEVEL: String?
        public var SWIFT_VERSION: String?
        public var TARGET_NAME: String?
        public var TARGET_BUILD_DIR: String?
        public var TVOS_DEPLOYMENT_TARGET: String?
        public var USE_HEADERMAP: String?
        public var USES_SWIFTPM_UNSAFE_FLAGS: String?
        public var WATCHOS_DEPLOYMENT_TARGET: String?
        public var MARKETING_VERSION: String?
        public var CURRENT_PROJECT_VERSION: String?
        public var platformSpecificSettings = [Platform: [Declaration: [String]]]()

        public init() {
            Platform.allCases.forEach { platform in
                platformSpecificSettings[platform] = [Declaration: [String]]()
                Declaration.allCases.forEach { declaration in
                    platformSpecificSettings[platform]![declaration] = ["$(inherited)"]
                }
            }
        }
    }
}

/// Repesents a filetype recognized by the Xcode build system. 
public struct XCBuildFileType: CaseIterable {
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
