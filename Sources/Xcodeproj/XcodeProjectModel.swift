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
        let mainGroup: Group
        var buildSettings: BuildSettingsTable
        var productGroup: Group?
        var projectDir: String
        var targets: [Target]
        init() {
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
        var path: String
        /// Determines the base path for the reference's relative path.
        var pathBase: RefPathBase
        /// Name of the reference, if different from the last path component
        /// (if not set, Xcode will use the last path component as the name).
        var name: String?

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
            /// The string form, suitable for use in an Xcode project file.
            var asString: String { return rawValue }
        }

        init(path: String, pathBase: RefPathBase = .groupDir, name: String? = nil) {
            self.path = path
            self.pathBase = pathBase
            self.name = name
        }
    }

    /// A reference to a file system entity (a file, folder, etc).
    public class FileReference: Reference {
        var objectID: String?
        var fileType: String?

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
        var subitems = [Reference]()

        /// Creates and appends a new Group to the list of subitems.
        /// The new group is returned so that it can be configured.
        @discardableResult public func addGroup(
            path: String,
            pathBase: RefPathBase = .groupDir,
            name: String? = nil
        ) -> Group {
            let group = Group(path: path, pathBase: pathBase, name: name)
            subitems.append(group)
            return group
        }

        /// Creates and appends a new FileReference to the list of subitems.
        @discardableResult public func addFileReference(
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
        var objectID: String?
        var name: String
        var productName: String
        var productType: ProductType?
        var buildSettings: BuildSettingsTable
        var buildPhases: [BuildPhase]
        var productReference: FileReference?
        var dependencies: [TargetDependency]
        public enum ProductType: String {
            case application = "com.apple.product-type.application"
            case staticArchive = "com.apple.product-type.library.static"
            case dynamicLibrary = "com.apple.product-type.library.dynamic"
            case framework = "com.apple.product-type.framework"
            case executable = "com.apple.product-type.tool"
            case unitTest = "com.apple.product-type.bundle.unit-test"
            var asString: String { return rawValue }
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
        @discardableResult public func addHeadersBuildPhase() -> HeadersBuildPhase {
            let phase = HeadersBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "sources" build phase, i.e. one that compiles sources and
        /// provides them to be linked into the executable code of the product.
        @discardableResult public func addSourcesBuildPhase() -> SourcesBuildPhase {
            let phase = SourcesBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "frameworks" build phase, i.e. one that links compiled code
        /// and libraries into the executable of the product.
        @discardableResult public func addFrameworksBuildPhase() -> FrameworksBuildPhase {
            let phase = FrameworksBuildPhase()
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "copy files" build phase, i.e. one that copies files to an
        /// arbitrary location relative to the product.
        @discardableResult public func addCopyFilesBuildPhase(dstDir: String) -> CopyFilesBuildPhase {
            let phase = CopyFilesBuildPhase(dstDir: dstDir)
            buildPhases.append(phase)
            return phase
        }

        /// Adds a "shell script" build phase, i.e. one that runs a custom
        /// shell script as part of the build.
        @discardableResult public func addShellScriptBuildPhase(script: String) -> ShellScriptBuildPhase {
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
        struct TargetDependency {
            unowned var target: Target
        }
    }

    /// Abstract base class for all build phases in a target.
    public class BuildPhase {
        var files: [BuildFile] = []

        /// Adds a new build file that refers to `fileRef`.
        @discardableResult public func addBuildFile(fileRef: FileReference) -> BuildFile {
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
        var dstDir: String
        init(dstDir: String) {
            self.dstDir = dstDir
        }
    }

    /// A "shell script" build phase, i.e. one that runs a custom shell script.
    public class ShellScriptBuildPhase: BuildPhase {
        var script: String
        init(script: String) {
            self.script = script
        }
    }

    /// A build file, representing the membership of a file reference in a
    /// build phase of a target.
    public class BuildFile {
        weak var fileRef: FileReference?
        init(fileRef: FileReference) {
            self.fileRef = fileRef
        }
    }

    /// A table of build settings, which for the sake of simplicity consists
    /// (in this simplified model) of a set of common settings, and a set of
    /// overlay settings for Debug and Release builds.  There can also be a
    /// file reference to an .xcconfig file on which to base the settings.
    public class BuildSettingsTable {
        /// Common build settings are in both generated configurations (Debug
        /// and Release).
        var common = BuildSettings()

        /// Debug build settings are overlaid over the common settings in the
        /// generated Debug configuration.
        /// FIXME: They are not currently, but should be, overlaid in a manner
        /// that preserves the semantics of `$(inherited)`.
        var debug = BuildSettings()

        /// Release build settings are overlaid over the common settings in the
        /// generated Release configuration.
        /// FIXME: They are not currently, but should be, overlaid in a manner
        /// that preserves the semantics of `$(inherited)`.
        var release = BuildSettings()

        /// An optional file reference to an .xcconfig file.
        var xcconfigFileRef: FileReference?

        /// A set of build settings, which is represented as a struct of optional
        /// build settings.  This is not optimally efficient, but it is great for
        /// code completion and type-checking.
        public struct BuildSettings {
            // Note: although some of these build settings sound like booleans,
            // they are all either strings or arrays of strings, because even
            // a boolean may be a macro reference expression.
            var CLANG_ENABLE_OBJC_ARC: String?
            var COMBINE_HIDPI_IMAGES: String?
            var COPY_PHASE_STRIP: String?
            var DEBUG_INFORMATION_FORMAT: String?
            var DEFINES_MODULE: String?
            var DYLIB_INSTALL_NAME_BASE: String?
            var EMBEDDED_CONTENT_CONTAINS_SWIFT: String?
            var ENABLE_NS_ASSERTIONS: String?
            var ENABLE_TESTABILITY: String?
            var FRAMEWORK_SEARCH_PATHS: [String]?
            var GCC_OPTIMIZATION_LEVEL: String?
            var HEADER_SEARCH_PATHS: [String]?
            var INFOPLIST_FILE: String?
            var LD_RUNPATH_SEARCH_PATHS: [String]?
            var LIBRARY_SEARCH_PATHS: [String]?
            var MACOSX_DEPLOYMENT_TARGET: String?
            var MODULEMAP_FILE: String?
            var ONLY_ACTIVE_ARCH: String?
            var OTHER_CFLAGS: [String]?
            var OTHER_LDFLAGS: [String]?
            var OTHER_SWIFT_FLAGS: [String]?
            var PRODUCT_BUNDLE_IDENTIFIER: String?
            var PRODUCT_MODULE_NAME: String?
            var PRODUCT_NAME: String?
            var PROJECT_NAME: String?
            var SDKROOT: String?
            var SKIP_INSTALL: String?
            var SUPPORTED_PLATFORMS: [String]?
            var SWIFT_ACTIVE_COMPILATION_CONDITIONS: String?
            var SWIFT_FORCE_STATIC_LINK_STDLIB: String?
            var SWIFT_FORCE_DYNAMIC_LINK_STDLIB: String?
            var SWIFT_OPTIMIZATION_LEVEL: String?
            var SWIFT_VERSION: String?
            var TARGET_NAME: String?
            var USE_HEADERMAP: String?
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
