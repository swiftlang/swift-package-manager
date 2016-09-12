/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------

 In an effort to provide:

  1. Unique reference identifiers
  2. Human readable reference identifiers
  3. Stable reference identifiers

 (as opposed to the generated UUIDs Xcode typically generates)

 We create identifiers with a constant-length unique prefix and
 a unique suffix where the suffix is the filename or module name
 and since we guarantee uniqueness at the PackageDescription
 layer for these properties we satisfy the above constraints.
*/

import Basic
import PackageModel
import PackageLoading

let rootObjectReference =                           "__RootObject_"
let rootBuildConfigurationListReference =           "___RootConfs_"
let rootDebugBuildConfigurationReference =          "_______Debug_"
let rootReleaseBuildConfigurationReference =        "_____Release_"
let rootGroupReference =                            "___RootGroup_"
let productsGroupReference =                        "____Products_"
let testProductsGroupReference =                    "TestProducts_"
let configsGroupReference =                         "_____Configs_"
let sourcesGroupReference =                         "_____Sources_"
let dependenciesGroupReference =                    "Dependencies_"
let testsGroupReference =                           "_______Tests_"
let linkPhaseFileRefPrefix =                        "_LinkFileRef_"
let sourceGroupFileRefPrefix =                      "__PBXFileRef_"
let compilePhaseFileRefPrefix =                     "__src_cc_ref_"

extension Module {
    var dependencyReference: String           { return "__Dependency_\(c99name)" }
    var productReference: String              { return "_____Product_\(c99name)" }
    var targetReference: String               { return "______Target_\(c99name)" }
    var groupReference: String                { return "_______Group_\(c99name)" }
    var configurationListReference: String    { return "_______Confs_\(c99name)" }
    var debugConfigurationReference: String   { return "___DebugConf_\(c99name)" }
    var releaseConfigurationReference: String { return "_ReleaseConf_\(c99name)" }
    var compilePhaseReference: String         { return "CompilePhase_\(c99name)" }
    var linkPhaseReference: String            { return "___LinkPhase_\(c99name)" }
    var shellScriptPhaseReference: String     { return "_ScriptPhase_\(c99name)" }
}

func fileRef(forLinkPhaseChild module: Module, from: Module) -> String {
    return linkPhaseFileRefPrefix + module.c99name + "_via_" + from.c99name
}

/// Generates and returns an id string for a source file module at a given path inside a root directory.  The contents of the generated id string is arbitrary, but a) will always be the same if the relative path from `srcroot` to `path` is the same, and b) will always be unique among the set of possible paths under `srcroot`.
private func fileRef(idSuffixForModuleSourceFile path: AbsolutePath, srcroot: AbsolutePath) -> String {
    // For the moment this does something quite simplistic, but which is still guaranteed to yield the same id for any given path and root, and that will yield unique ids for all the paths in a set (as long as all are subpaths of the root).
    let path = path.relative(to: srcroot).asString
    return path.characters.map{ c -> String in
        switch c {
        case "\\":
            return "\\\\"
        case "'":
            return "\'"
        default:
            return "\(c)"
        }
    }.joined(separator: "")
}

/// Returns the (refId, path) tuple for a file with a given subpath inside a root directory.
func fileRef(inProjectRoot subpath: RelativePath, srcroot: AbsolutePath) -> (refId: String, path: AbsolutePath) {
    let path = srcroot.appending(subpath)
    let idSuffix = fileRef(idSuffixForModuleSourceFile: path, srcroot: srcroot)
    return (refId: "'\(sourceGroupFileRefPrefix)\(idSuffix)'", path: path)
}

/// Returns the (refId, path) tuple for the Info.plist file for a particular module.
func fileRef(ofInfoPlistFor module: Module, srcroot: AbsolutePath) -> (refId: String, path: AbsolutePath) {
    let path = srcroot.appending(component: module.infoPlistFileName)
    let idSuffix = module.infoPlistFileName
    return (refId: "\(sourceGroupFileRefPrefix)\(idSuffix)", path: path)
}

/// Returns an array of (refId, path, bflId) tuples of the source files in a module, where `refId` is the object id string of the `PBXFileReference` (in the groups-and-files hierarchy) and `bflId` is the object id string of the corresponding `PBXBuildFile` (in the build phase's file list).
func fileRefs(forModuleSources module: Module, srcroot: AbsolutePath) -> [(refId: String, path: AbsolutePath, bflId: String)] {
    let moduleRoot = module.sources.root
    return module.sources.relativePaths.map { relPath in
        let path = moduleRoot.appending(relPath)
        let idSuffix = fileRef(idSuffixForModuleSourceFile: path, srcroot: srcroot)
        return (refId: "'\(sourceGroupFileRefPrefix)\(idSuffix)'", path: path, bflId: "'\(compilePhaseFileRefPrefix)\(idSuffix)'")
    }
}


extension Module  {
    var isLibrary: Bool {
        return type == .library
    }

    var infoPlistFileName: String {
        return "\(c99name)_Info.plist"
    }

    var productType: String {
        if isTest {
            return "com.apple.product-type.bundle.unit-test"
        } else if isLibrary {
            return "com.apple.product-type.framework"
        } else {
            return "com.apple.product-type.tool"
        }
    }

    var explicitFileType: String {
        if isTest {
            return "compiled.mach-o.wrapper.cfbundle"
        } else if isLibrary {
            return "wrapper.framework"
        } else {
            return "compiled.mach-o.executable"
        }
    }

    var productPath: RelativePath {
        if isTest {
            return RelativePath("\(c99name).xctest")
        } else if isLibrary {
            return RelativePath("\(c99name).framework")
        } else {
            return RelativePath(name)
        }
    }

    var linkPhaseFileRefs: [(dependency: Module, fileRef: String)] {
        return recursiveDependencies.filter{ $0.type != .systemModule }.map{ (dependency: $0, fileRef: fileRef(forLinkPhaseChild: $0, from: self)) }
    }

    var nativeTargetDependencies: String {
        return dependencies.filter{ $0.type != .systemModule }.map{ $0.dependencyReference }.joined(separator: ", ")
    }

    var productName: String {
        if isLibrary && !isTest {
            // you can go without a lib prefix, but something unexpected will break
            return "'lib$(TARGET_NAME)'"
        } else {
            return "'$(TARGET_NAME)'"
        }
    }

    var headerSearchPaths: (key: String, value: Any)? {
        let headerPathKey = "HEADER_SEARCH_PATHS"
        var headerPaths = dependencies.flatMap { module -> AbsolutePath? in
            switch module {
            case let cModule as CModule:
                return cModule.path
            case let clangModule as ClangModule:
                return clangModule.includeDir
            default:
                return nil
            }
        }

        // For ClangModules add implicit search path to its own include directory.
        if case let clangModule as ClangModule = self {
            headerPaths.append(clangModule.includeDir)
        }

        guard !headerPaths.isEmpty else { return nil }
        
        return (headerPathKey, headerPaths.map { $0.asString } )
    }

    func getDebugBuildSettings(_ options: XcodeprojOptions, xcodeProjectPath: AbsolutePath) throws -> String {
        var buildSettings = try getCommonBuildSettings(options, xcodeProjectPath: xcodeProjectPath)
        if let headerSearchPaths = headerSearchPaths {
            buildSettings[headerSearchPaths.key] = headerSearchPaths.value
        }
        return toPlist(buildSettings).serialize()
    }

    func getReleaseBuildSettings(_ options: XcodeprojOptions, xcodeProjectPath: AbsolutePath) throws -> String {
        var buildSettings = try getCommonBuildSettings(options, xcodeProjectPath: xcodeProjectPath)
        if let headerSearchPaths = headerSearchPaths {
            buildSettings[headerSearchPaths.key] = headerSearchPaths.value
        }
        return toPlist(buildSettings).serialize()
    }

    /// Converts build settings dictionary to a Plist object.
    ///
    /// Adds string values in dictionaries as is and array values are quoted and then converted
    /// to a string joined by whitespace.
    private func toPlist(_ buildSettings: [String: Any]) -> Plist {
        var buildSettingsPlist = [String: Plist]()
        for (k, v) in buildSettings {
            switch v {
            case let value as String:
                buildSettingsPlist[k] = .string(value)
            case let value as [String]:
                let escaped = value.map { "\"" + Plist.escape(string: $0) + "\"" }.joined(separator: " ")
                buildSettingsPlist[k] = .string(escaped)
            default:
                fatalError("build setting dictionary should only contain String or [String]")
            }
        }
        return .dictionary(buildSettingsPlist)
    }

    private func getCommonBuildSettings(_ options: XcodeprojOptions, xcodeProjectPath: AbsolutePath) throws -> [String: Any] {
        var buildSettings = [String: Any]()
        let plistPath = xcodeProjectPath.appending(component: infoPlistFileName)

        // Add default library search path to the directory where symlinks to C target framework
        // binaries will be put with name `lib<library-name>.dylib` so that autolinking
        // can proceed without providing another modulemap for Xcode projects.
        // See: https://bugs.swift.org/browse/SR-2465
        if recursiveDependencies.first(where: { $0 is ClangModule }) != nil {
            buildSettings["LIBRARY_SEARCH_PATHS"] = ["$(PROJECT_TEMP_DIR)/SymlinkLibs/"]
        }

        if isTest {
            buildSettings["EMBEDDED_CONTENT_CONTAINS_SWIFT"] = "YES"

            //FIXME this should not be required
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "@loader_path/../Frameworks"

            buildSettings["INFOPLIST_FILE"] = plistPath.relative(to: xcodeProjectPath.parentDirectory).asString
        } else {
            // We currently force a search path to the toolchain, since we
            // cannot establish an expected location for the Swift standard
            // libraries.
            //
            // This means the built binaries are not suitable for distribution,
            // among other things.
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = ["$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"]
            if isLibrary {
                buildSettings["ENABLE_TESTABILITY"] = "YES"

                // Set a product name consistent with the conventions for
                // dynamic libraries.
                //
                // This is important for SwiftPM itself, because the LLVM JIT
                // only will search for `lib<foo>` when doing dynamic loading,
                // and that is the mechanism that we currently use to "load" the
                // `Package.swift` manifest.
                //
                // FIXME: This might not be what we generally want, and if we
                // moved to producing frameworks it wouldn't work at all. We
                // need to design a mechanism by which SwiftPM can override the
                // PRODUCT_NAME for PackageDescription without imposing this
                // default behavior on all packages.

                buildSettings["PRODUCT_NAME"] = "$(TARGET_NAME:c99extidentifier)"
                buildSettings["INFOPLIST_FILE"] = plistPath.relative(to: xcodeProjectPath.parentDirectory).asString

                buildSettings["PRODUCT_MODULE_NAME"] = "$(TARGET_NAME:c99extidentifier)"

                // FIXME: This should be user speficiable
                buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = c99name
            } else {
                // override default behavior, instead link dynamically
                buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = "NO"
                buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] = "YES"

                // Set the runpath search paths so that we can find libraries
                // built adjacent to ourselves (e.g., in the Xcode
                // `BUILT_PRODUCTS_DIR`).
                //
                // It would be nice to pick another value here which would make
                // more sense when use in a real deployment scenario (one
                // example would be `@executable_path/../lib` but there are
                // other problems to solve first, e.g. how to deal with the
                // Swift standard library paths).
                buildSettings["LD_RUNPATH_SEARCH_PATHS"] = buildSettings["LD_RUNPATH_SEARCH_PATHS"] as! [String] + ["@executable_path"]
            }
        }

        if let pkgArgs = try? self.pkgConfigArgs() {
            buildSettings["OTHER_LDFLAGS"] = ["$(inherited)"] + pkgArgs.libs
            buildSettings["OTHER_SWIFT_FLAGS"] = ["$(inherited)"] + pkgArgs.cFlags
        }

        // Add framework search path to build settings.
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = "$(PLATFORM_DIR)/Developer/Library/Frameworks"

        // Generate modulemap for a ClangModule if not provided by user and add to build settings.
        if case let clangModule as ClangModule = self, clangModule.type == .library {
            buildSettings["DEFINES_MODULE"] = "YES"
            let moduleMapPath: AbsolutePath
            // If user provided the modulemap no need to generate.
            if isFile(clangModule.moduleMapPath) {
                moduleMapPath = clangModule.moduleMapPath
            } else {
                // Generate and drop the modulemap inside Xcodeproj folder.
                let path = xcodeProjectPath.appending(components: "GeneratedModuleMap", clangModule.c99name)
                var moduleMapGenerator = ModuleMapGenerator(for: clangModule)
                try moduleMapGenerator.generateModuleMap(inDir: path)
                moduleMapPath = path.appending(component: moduleMapFilename)
            }

            buildSettings["MODULEMAP_FILE"] = moduleMapPath.relative(to: xcodeProjectPath.parentDirectory).asString
        }

        // At the moment, set the Swift version to 3 (we will need to make this dynamic), but for now this is necessary.
        buildSettings["SWIFT_VERSION"] = "3.0"
        
        // Defined for regular `swift build` instantiations, so also should be defined here.
        buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "SWIFT_PACKAGE"

        return buildSettings
    }
}
