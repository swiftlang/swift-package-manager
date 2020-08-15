/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------------------

 A very simple rendition of the Xcode project model.  There is only sufficient
 functionality to allow creation of Xcode projects in a somewhat readable way,
 and serialization to .xcodeproj plists.  There is no consistency checking to
 ensure, for example, that build settings have valid values, dependency cycles
 are not created, etc.
 
 Everything here is geared toward supporting project generation.  The intended
 usage model is for custom logic to build up a project using Xcode terminology
 (e.g. "group", "reference", "target", "build phase"), but there is almost no
 provision for modifying the model after it has been built up.  The intent is
 to create it as desired from the start.
 
 Rather than try to represent everything that Xcode's project model supports,
 the approach is to start small and to add functionality as needed.
 
 Note that this API represents only the project model — there is no notion of
 workspaces, schemes, etc (although schemes are represented individually in a
 separate API).  The notion of build settings is also somewhat different from
 what it is in Xcode:  instead of an open-ended mapping of build configuration
 names to dictionaries of build settings, here there is a single set of common
 build settings plus two overlay sets for debug and release.  The generated
 project has just the two Debug and Release configurations, created by merging
 the common set into the release and debug sets.  This allows a more natural
 configuration of the settings, since most values are the same between Debug
 and Release.  Also, the build settings themselves are represented as structs
 of named fields, instead of dictionaries with arbitrary name strings as keys.
 
 It is expected that some of these simplifications will need to be lifted over
 time, based on need.  That should be done carefully, however, to avoid ending
 up with an overly complicated model.
 
 Some things that are incomplete in even this first model:
 - copy files build phases are incomplete
 - shell script build phases are incomplete
 - file types in file references are specified using strings; should be enums
   so that the client doesn't have to hardcode the mapping to Xcode file type
   identifiers
 - debug and release settings override common settings; they should be merged
   in a way that respects `$(inhertied)` when the same setting is defined in
   common and in debug or release
 - there is no good way to control the ordering of the `Products` group in the
   main group; it needs to be added last in order to appear after the other
   references
*/

public struct Xcode {

    /// An Xcode project, consisting of a tree of groups and file references,
    /// a list of targets, and some additional information.  Note that schemes
    /// are outside of the project data model.
    public class Project {
        public let mainGroup: Group
        public var buildSettings: BuildSettingsTable
        public var productGroup: Group?
        public var projectDir: String
        public var targets: [Target]
        public init() {
            self.mainGroup = Group(path: "")
            self.buildSettings = BuildSettingsTable()
            self.productGroup = nil
            self.projectDir = ""
            self.targets = []
        }

        /// Creates and adds a new target (which does not initially have any
        /// build phases).
        public func addTarget(objectID: String? = nil, productType: Target.ProductType?, name: String) -> Target {
            let target = Target(objectID: objectID, productType: productType, name: name)
            targets.append(target)
            return target
        }
    }

    /// Abstract base class for all items in the group hierarhcy.
    public class Reference {
        /// Relative path of the reference.  It is usually a literal, but may
        /// in fact contain build settings.
        public var path: String
        /// Determines the base path for the reference's relative path.
        public var pathBase: RefPathBase
        /// Name of the reference, if different from the last path component
        /// (if not set, Xcode will use the last path component as the name).
        public var name: String?

        /// Determines the base path for a reference's relative path (this is
        /// what for some reason is called a "source tree" in Xcode).
        public enum RefPathBase: String {
            /// Indicates that the path is relative to the source root (i.e.
            /// the "project directory").
            case projectDir = "SOURCE_ROOT"
            /// Indicates that the path is relative to the path of the parent
            /// group.
            case groupDir = "<group>"
            /// Indicates that the path is relative to the effective build
            /// directory (which varies depending on active scheme, active run
            /// destination, or even an overridden build setting.
            case buildDir = "BUILT_PRODUCTS_DIR"
        }

        public init(path: String, pathBase: RefPathBase = .groupDir, name: String? = nil) {
            self.path = path
            self.pathBase = pathBase
            self.name = name
        }
    }

    /// A reference to a file system entity (a file, folder, etc).
    public class FileReference: Reference {
        public var objectID: String?
        public var fileType: String?

        init(path: String, pathBase: RefPathBase = .groupDir, name: String? = nil, fileType: String? = nil, objectID: String? = nil) {
            super.init(path: path, pathBase: pathBase, name: name)
            self.objectID = objectID
            self.fileType = fileType
        }
    }

    /// A group that can contain References (FileReferences and other Groups).
    /// The resolved path of a group is used as the base path for any child
    /// references whose source tree type is GroupRelative.
    public class Group: Reference {
        public var subitems = [Reference]()

        /// Creates and appends a new Group to the list of subitems.
        /// The new group is returned so that it can be configured.
        @discardableResult
        public func addGroup(
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil
        ) -> Group {
            let group = Group(path: path, pathBase: pathBase, name: name)
            subitems.append(group)
            return group
        }

        /// Creates and appends a new FileReference to the list of subitems.
        @discardableResult
        public func addFileReference(
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil,
            fileType: String? = nil,
            objectID: String? = nil
        ) -> FileReference {
            let fref = FileReference(path: path, pathBase: pathBase, name: name, fileType: fileType, objectID: objectID)
            subitems.append(fref)
            return fref
        }
    }

    /// An Xcode target, representing a single entity to build.
    public class Target {
        public var objectID: String?
        public var name: String
        public var productName: String
        public var productType: ProductType?
        public var buildSettings: BuildSettingsTable
        public var buildPhases: [BuildPhase]
        public var productReference: FileReference?
        public var dependencies: [TargetDependency]
        public enum ProductType: String {
            case application = "com.apple.product-type.application"
            case staticArchive = "com.apple.product-type.library.static"
            case dynamicLibrary = "com.apple.product-type.library.dynamic"
            case framework = "com.apple.product-type.framework"
            case executable = "com.apple.product-type.tool"
            case unitTest = "com.apple.product-type.bundle.unit-test"
        }
        init(objectID: String?, productType: ProductType?, name: String) {
            self.objectID = objectID
            self.name = name
            self.productType = productType
            self.productName = name
            self.buildSettings = BuildSettingsTable()
            self.buildPhases = []
            self.dependencies = []
        }

        // FIXME: There's a lot repetition in these methods; using generics to
        // try to avoid that raised other issues in terms of requirements on
        // the Reference class, though.

        /// Adds a "headers" build phase, i.e. one that copies headers into a
        /// directory of the product, after suitable processing.
        @discardableResult
        public func addHeadersBuildPhase() -> HeadersBuildPhase {
            let phase = HeadersBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "sources" build phase, i.e. one that compiles sources and
        /// provides them to be linked into the executable code of the product.
        @discardableResult
        public func addSourcesBuildPhase() -> SourcesBuildPhase {
            let phase = SourcesBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "frameworks" build phase, i.e. one that links compiled code
        /// and libraries into the executable of the product.
        @discardableResult
        public func addFrameworksBuildPhase() -> FrameworksBuildPhase {
            let phase = FrameworksBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "copy files" build phase, i.e. one that copies files to an
        /// arbitrary location relative to the product.
        @discardableResult
        public func addCopyFilesBuildPhase(dstDir: String) -> CopyFilesBuildPhase {
            let phase = CopyFilesBuildPhase(dstDir: dstDir)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "shell script" build phase, i.e. one that runs a custom
        /// shell script as part of the build.
        @discardableResult
        public func addShellScriptBuildPhase(script: String) -> ShellScriptBuildPhase {
            let phase = ShellScriptBuildPhase(script: script)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a dependency on another target.
        /// FIXME: We do not check for cycles.  Should we?  This is an extremely
        /// minimal API so it's not clear that we should.
        public func addDependency(on target: Target) {
            dependencies.append(TargetDependency(target: target))
        }

        /// A simple wrapper to prevent ownership cycles in the `dependencies`
        /// property.
        public struct TargetDependency {
            public unowned var target: Target
        }
    }

    /// Abstract base class for all build phases in a target.
    public class BuildPhase {
        public var files: [BuildFile] = []

        /// Adds a new build file that refers to `fileRef`.
        @discardableResult
        public func addBuildFile(fileRef: FileReference) -> BuildFile {
            let buildFile = BuildFile(fileRef: fileRef)
            files.append(buildFile)
            return buildFile
        }
    }

    /// A "headers" build phase, i.e. one that copies headers into a directory
    /// of the product, after suitable processing.
    public class HeadersBuildPhase: BuildPhase {
        // Nothing extra yet.
    }

    /// A "sources" build phase, i.e. one that compiles sources and provides
    /// them to be linked into the executable code of the product.
    public class SourcesBuildPhase: BuildPhase {
        // Nothing extra yet.
    }

    /// A "frameworks" build phase, i.e. one that links compiled code and
    /// libraries into the executable of the product.
    public class FrameworksBuildPhase: BuildPhase {
        // Nothing extra yet.
    }

    /// A "copy files" build phase, i.e. one that copies files to an arbitrary
    /// location relative to the product.
    public class CopyFilesBuildPhase: BuildPhase {
        public var dstDir: String
        init(dstDir: String) {
            self.dstDir = dstDir
        }
    }

    /// A "shell script" build phase, i.e. one that runs a custom shell script.
    public class ShellScriptBuildPhase: BuildPhase {
        public var script: String
        init(script: String) {
            self.script = script
        }
    }

    /// A build file, representing the membership of a file reference in a
    /// build phase of a target.
    public class BuildFile {
        public weak var fileRef: FileReference?
        init(fileRef: FileReference) {
            self.fileRef = fileRef
        }

        var settings = Settings()

        /// A set of file settings.
        public struct Settings {
            public var ATTRIBUTES: [String]?

            public init() {
            }
        }
    }

    /// A table of build settings, which for the sake of simplicity consists
    /// (in this simplified model) of a set of common settings, and a set of
    /// overlay settings for Debug and Release builds.  There can also be a
    /// file reference to an .xcconfig file on which to base the settings.
    public class BuildSettingsTable {
        /// Common build settings are in both generated configurations (Debug
        /// and Release).
        public var common = BuildSettings()

        /// Debug build settings are overlaid over the common settings in the
        /// generated Debug configuration.
        public var debug = BuildSettings()

        /// Release build settings are overlaid over the common settings in the
        /// generated Release configuration.
        public var release = BuildSettings()

        /// An optional file reference to an .xcconfig file.
        public var xcconfigFileRef: FileReference?

        public init() {
        }

        /// A set of build settings, which is represented as a struct of optional
        /// build settings.  This is not optimally efficient, but it is great for
        /// code completion and type-checking.
        public struct BuildSettings {
            // Note: although some of these build settings sound like booleans,
            // they are all either strings or arrays of strings, because even
            // a boolean may be a macro reference expression.
            public var CLANG_CXX_LANGUAGE_STANDARD: String?
            public var CLANG_ENABLE_MODULES: String?
            public var CLANG_ENABLE_OBJC_ARC: String?
            public var COMBINE_HIDPI_IMAGES: String?
            public var COPY_PHASE_STRIP: String?
            public var CURRENT_PROJECT_VERSION: String?
            public var DEBUG_INFORMATION_FORMAT: String?
            public var DEFINES_MODULE: String?
            public var DYLIB_INSTALL_NAME_BASE: String?
            public var EMBEDDED_CONTENT_CONTAINS_SWIFT: String?
            public var ENABLE_NS_ASSERTIONS: String?
            public var ENABLE_TESTABILITY: String?
            public var FRAMEWORK_SEARCH_PATHS: [String]?
            public var GCC_C_LANGUAGE_STANDARD: String?
            public var GCC_OPTIMIZATION_LEVEL: String?
            public var GCC_PREPROCESSOR_DEFINITIONS: [String]?
            public var HEADER_SEARCH_PATHS: [String]?
            public var INFOPLIST_FILE: String?
            public var LD_RUNPATH_SEARCH_PATHS: [String]?
            public var LIBRARY_SEARCH_PATHS: [String]?
            public var MACOSX_DEPLOYMENT_TARGET: String?
            public var IPHONEOS_DEPLOYMENT_TARGET: String?
            public var TVOS_DEPLOYMENT_TARGET: String?
            public var WATCHOS_DEPLOYMENT_TARGET: String?
            public var MODULEMAP_FILE: String?
            public var ONLY_ACTIVE_ARCH: String?
            public var OTHER_CFLAGS: [String]?
            public var OTHER_CPLUSPLUSFLAGS: [String]?
            public var OTHER_LDFLAGS: [String]?
            public var OTHER_SWIFT_FLAGS: [String]?
            public var PRODUCT_BUNDLE_IDENTIFIER: String?
            public var PRODUCT_MODULE_NAME: String?
            public var PRODUCT_NAME: String?
            public var PROJECT_NAME: String?
            public var SDKROOT: String?
            public var SKIP_INSTALL: String?
            public var SUPPORTED_PLATFORMS: [String]?
            public var SWIFT_ACTIVE_COMPILATION_CONDITIONS: [String]?
            public var SWIFT_FORCE_STATIC_LINK_STDLIB: String?
            public var SWIFT_FORCE_DYNAMIC_LINK_STDLIB: String?
            public var SWIFT_OPTIMIZATION_LEVEL: String?
            public var SWIFT_VERSION: String?
            public var TARGET_NAME: String?
            public var USE_HEADERMAP: String?
            public var LD: String?

            public init(
                CLANG_CXX_LANGUAGE_STANDARD: String? = nil,
                CLANG_ENABLE_MODULES: String? = nil,
                CLANG_ENABLE_OBJC_ARC: String? = nil,
                COMBINE_HIDPI_IMAGES: String? = nil,
                COPY_PHASE_STRIP: String? = nil,
                CURRENT_PROJECT_VERSION: String? = nil,
                DEBUG_INFORMATION_FORMAT: String? = nil,
                DEFINES_MODULE: String? = nil,
                DYLIB_INSTALL_NAME_BASE: String? = nil,
                EMBEDDED_CONTENT_CONTAINS_SWIFT: String? = nil,
                ENABLE_NS_ASSERTIONS: String? = nil,
                ENABLE_TESTABILITY: String? = nil,
                FRAMEWORK_SEARCH_PATHS: [String]? = nil,
                GCC_C_LANGUAGE_STANDARD: String? = nil,
                GCC_OPTIMIZATION_LEVEL: String? = nil,
                GCC_PREPROCESSOR_DEFINITIONS: [String]? = nil,
                HEADER_SEARCH_PATHS: [String]? = nil,
                INFOPLIST_FILE: String? = nil,
                LD_RUNPATH_SEARCH_PATHS: [String]? = nil,
                LIBRARY_SEARCH_PATHS: [String]? = nil,
                MACOSX_DEPLOYMENT_TARGET: String? = nil,
                IPHONEOS_DEPLOYMENT_TARGET: String? = nil,
                TVOS_DEPLOYMENT_TARGET: String? = nil,
                WATCHOS_DEPLOYMENT_TARGET: String? = nil,
                MODULEMAP_FILE: String? = nil,
                ONLY_ACTIVE_ARCH: String? = nil,
                OTHER_CFLAGS: [String]? = nil,
                OTHER_CPLUSPLUSFLAGS: [String]? = nil,
                OTHER_LDFLAGS: [String]? = nil,
                OTHER_SWIFT_FLAGS: [String]? = nil,
                PRODUCT_BUNDLE_IDENTIFIER: String? = nil,
                PRODUCT_MODULE_NAME: String? = nil,
                PRODUCT_NAME: String? = nil,
                PROJECT_NAME: String? = nil,
                SDKROOT: String? = nil,
                SKIP_INSTALL: String? = nil,
                SUPPORTED_PLATFORMS: [String]? = nil,
                SWIFT_ACTIVE_COMPILATION_CONDITIONS: [String]? = nil,
                SWIFT_FORCE_STATIC_LINK_STDLIB: String? = nil,
                SWIFT_FORCE_DYNAMIC_LINK_STDLIB: String? = nil,
                SWIFT_OPTIMIZATION_LEVEL: String? = nil,
                SWIFT_VERSION: String? = nil,
                TARGET_NAME: String? = nil,
                USE_HEADERMAP: String? = nil,
                LD: String? = nil
            ) {
                self.CLANG_CXX_LANGUAGE_STANDARD = CLANG_CXX_LANGUAGE_STANDARD
                self.CLANG_ENABLE_MODULES = CLANG_ENABLE_MODULES
                self.CLANG_ENABLE_OBJC_ARC = CLANG_CXX_LANGUAGE_STANDARD
                self.COMBINE_HIDPI_IMAGES = COMBINE_HIDPI_IMAGES
                self.COPY_PHASE_STRIP = COPY_PHASE_STRIP
                self.CURRENT_PROJECT_VERSION = CURRENT_PROJECT_VERSION
                self.DEBUG_INFORMATION_FORMAT = DEBUG_INFORMATION_FORMAT
                self.DEFINES_MODULE = DEFINES_MODULE
                self.DYLIB_INSTALL_NAME_BASE = DYLIB_INSTALL_NAME_BASE
                self.EMBEDDED_CONTENT_CONTAINS_SWIFT = EMBEDDED_CONTENT_CONTAINS_SWIFT
                self.ENABLE_NS_ASSERTIONS = ENABLE_NS_ASSERTIONS
                self.ENABLE_TESTABILITY = ENABLE_TESTABILITY
                self.FRAMEWORK_SEARCH_PATHS = FRAMEWORK_SEARCH_PATHS
                self.GCC_C_LANGUAGE_STANDARD = GCC_C_LANGUAGE_STANDARD
                self.GCC_OPTIMIZATION_LEVEL = GCC_OPTIMIZATION_LEVEL
                self.GCC_PREPROCESSOR_DEFINITIONS = GCC_PREPROCESSOR_DEFINITIONS
                self.HEADER_SEARCH_PATHS = HEADER_SEARCH_PATHS
                self.INFOPLIST_FILE = INFOPLIST_FILE
                self.LD_RUNPATH_SEARCH_PATHS = LD_RUNPATH_SEARCH_PATHS
                self.LIBRARY_SEARCH_PATHS = LIBRARY_SEARCH_PATHS
                self.MACOSX_DEPLOYMENT_TARGET = MACOSX_DEPLOYMENT_TARGET
                self.IPHONEOS_DEPLOYMENT_TARGET = IPHONEOS_DEPLOYMENT_TARGET
                self.TVOS_DEPLOYMENT_TARGET = TVOS_DEPLOYMENT_TARGET
                self.WATCHOS_DEPLOYMENT_TARGET = WATCHOS_DEPLOYMENT_TARGET
                self.MODULEMAP_FILE = MODULEMAP_FILE
                self.ONLY_ACTIVE_ARCH = ONLY_ACTIVE_ARCH
                self.OTHER_CFLAGS = OTHER_CFLAGS
                self.OTHER_CPLUSPLUSFLAGS = OTHER_CPLUSPLUSFLAGS
                self.OTHER_LDFLAGS = OTHER_LDFLAGS
                self.OTHER_SWIFT_FLAGS = OTHER_SWIFT_FLAGS
                self.PRODUCT_BUNDLE_IDENTIFIER = PRODUCT_BUNDLE_IDENTIFIER
                self.PRODUCT_MODULE_NAME = PRODUCT_MODULE_NAME
                self.PRODUCT_NAME = PRODUCT_NAME
                self.PROJECT_NAME = PROJECT_NAME
                self.SDKROOT = SDKROOT
                self.SKIP_INSTALL = SKIP_INSTALL
                self.SUPPORTED_PLATFORMS = SUPPORTED_PLATFORMS
                self.SWIFT_ACTIVE_COMPILATION_CONDITIONS = SWIFT_ACTIVE_COMPILATION_CONDITIONS
                self.SWIFT_FORCE_STATIC_LINK_STDLIB = SWIFT_FORCE_STATIC_LINK_STDLIB
                self.SWIFT_FORCE_DYNAMIC_LINK_STDLIB = SWIFT_FORCE_DYNAMIC_LINK_STDLIB
                self.SWIFT_OPTIMIZATION_LEVEL = SWIFT_OPTIMIZATION_LEVEL
                self.SWIFT_VERSION = SWIFT_VERSION
                self.TARGET_NAME = TARGET_NAME
                self.USE_HEADERMAP = USE_HEADERMAP
                self.LD = LD
            }
        }
    }
}

/// Adds the abililty to append to an option array of strings that hasn't yet
/// been created.
/// FIXME: While we want the end result of being able to say `FLAGS += ["-O"]`
/// it is probably not how we want to implement it, since it changes behavior
/// for all arrays of string.  Instead, we should probably have a build setting
/// struct that wraps a string, and then we can write this in terms of just
/// build settings.
public func += (lhs: inout [String]?, rhs: [String]) {
    if lhs == nil {
        lhs = rhs
    } else {
        lhs = lhs! + rhs
    }
}
