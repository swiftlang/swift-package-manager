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

import struct Utility.Path
import PackageType

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

extension XcodeModuleProtocol {
    var dependencyReference: String           { return "__Dependency_\(c99name)" }
    var productReference: String              { return "_____Product_\(c99name)" }
    var targetReference: String               { return "______Target_\(c99name)" }
    var groupReference: String                { return "_______Group_\(c99name)" }
    var configurationListReference: String    { return "_______Confs_\(c99name)" }
    var debugConfigurationReference: String   { return "___DebugConf_\(c99name)" }
    var releaseConfigurationReference: String { return "_ReleaseConf_\(c99name)" }
    var compilePhaseReference: String         { return "CompilePhase_\(c99name)" }
    var linkPhaseReference: String            { return "___LinkPhase_\(c99name)" }
}

func fileRef(forLinkPhaseChild module: XcodeModuleProtocol) -> String {
    return linkPhaseFileRefPrefix + module.c99name
}

private func fileRef(suffixForModuleSourceFile path: String, srcroot: String) -> String {
    let path = Path(path).relative(to: srcroot)
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

func fileRef(inProjectRoot name: String, srcroot: String) -> (String, String, String) {
    let suffix = fileRef(suffixForModuleSourceFile: name, srcroot: srcroot)
    return ("'\(sourceGroupFileRefPrefix)\(suffix)'", name, Path.join(srcroot, name))
}

func fileRefs(forModuleSources module: XcodeModuleProtocol, srcroot: String) -> [(String, String)] {
    return module.sources.relativePaths.map { relativePath in
        let path = Path.join(module.sources.root, relativePath)
        let suffix = fileRef(suffixForModuleSourceFile: path, srcroot: srcroot)
        return ("'\(sourceGroupFileRefPrefix)\(suffix)'", relativePath)
    }
}

func fileRefs(forCompilePhaseSourcesInModule module: XcodeModuleProtocol, srcroot: String) -> [(String, String)] {
    return fileRefs(forModuleSources: module, srcroot: srcroot).map { ref1, relativePath in
        let path = Path.join(module.sources.root, relativePath)
        let suffix = fileRef(suffixForModuleSourceFile: path, srcroot: srcroot)
        return (ref1, "'\(compilePhaseFileRefPrefix)\(suffix)'")
    }
}

extension XcodeModuleProtocol  {

    private var isLibrary: Bool {
        return type == .Library
    }

    var productType: String {
        if self is TestModule {
            return "com.apple.product-type.bundle.unit-test"
        } else if isLibrary {
            return "com.apple.product-type.library.dynamic"
        } else {
            return "com.apple.product-type.tool"
        }
    }

    var explicitFileType: String {
        func suffix() -> String {
            if self is TestModule {
                return "wrapper.cfbundle"
            } else if isLibrary {
                return "dylib"
            } else {
                return "executable"
            }
        }
        return "compiled.mach-o.\(suffix())"
    }



    var productPath: String {
        if self is TestModule {
            return "\(c99name).xctest"
        } else if isLibrary {
            return "\(c99name).dylib"
        } else {
            return name
        }
    }

    var linkPhaseFileRefs: String {
        return recursiveDependencies.flatMap { $0 as? XcodeModuleProtocol }.map{ fileRef(forLinkPhaseChild: $0) }.joined(separator: ", ")
    }

    var nativeTargetDependencies: String {
        return dependencies.flatMap { $0 as? XcodeModuleProtocol }.map{ $0.dependencyReference }.joined(separator: ", ")
    }

    var productName: String {
        if isLibrary && !(self is TestModule) {
            // you can go without a lib prefix, but something unexpected will break
            return "'lib$(TARGET_NAME)'"
        } else {
            return "'$(TARGET_NAME)'"
        }
    }

    var headerSearchPaths: (key: String, value: String)? {
        let headerPathKey = "HEADER_SEARCH_PATHS"
        let headerPaths = dependencies.filter{$0 is CModule}.map{($0 as! CModule).path}

        guard !headerPaths.isEmpty else { return nil }

        if headerPaths.count == 1, let first = headerPaths.first {
            return (headerPathKey, first)
        }

        let headerPathValue = headerPaths.joined(separator: " ")
        
        return (headerPathKey, headerPathValue)
    }

    func getDebugBuildSettings(_ options: XcodeprojOptions) -> String {
        var buildSettings = getCommonBuildSettings(options)
        buildSettings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        if let headerSearchPaths = headerSearchPaths {
            buildSettings[headerSearchPaths.key] = headerSearchPaths.value
        }
        // FIXME: Need to honor actual quoting rules here.
        return buildSettings.map{ "\($0) = '\($1)';" }.joined(separator: " ")
    }

    func getReleaseBuildSettings(_ options: XcodeprojOptions) -> String {
        var buildSettings = getCommonBuildSettings(options)
        if let headerSearchPaths = headerSearchPaths {
            buildSettings[headerSearchPaths.key] = headerSearchPaths.value
        }
        // FIXME: Need to honor actual quoting rules here.
        return buildSettings.map{ "\($0) = '\($1)';" }.joined(separator: " ")
    }

    private func getCommonBuildSettings(_ options: XcodeprojOptions) ->[String: String] {
        var buildSettings = [String: String]()

        if self is TestModule {
            buildSettings["EMBEDDED_CONTENT_CONTAINS_SWIFT"] = "YES"

            //FIXME this should not be required
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "@loader_path/../Frameworks"

        } else {
            // We currently force a search path to the toolchain, since we
            // cannot establish an expected location for the Swift standard
            // libraries.
            //
            // This means the built binaries are not suitable for distribution,
            // among other things.
            buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"
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
                buildSettings["PRODUCT_NAME"] = "lib$(TARGET_NAME)"
                buildSettings["PRODUCT_MODULE_NAME"] = "$(TARGET_NAME:c99extidentifier)"
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
                buildSettings["LD_RUNPATH_SEARCH_PATHS"] = buildSettings["LD_RUNPATH_SEARCH_PATHS"]! + " @executable_path"
            }
        }

        return buildSettings
    }
}


extension XcodeModuleProtocol {
    var blueprintIdentifier: String {
        return targetReference
    }

    var buildableName: String {
        if isLibrary && !(self is TestModule) {
            return "lib\(productPath)"
        } else {
            return productPath
        }
    }

    var blueprintName: String {
        return name
    }
}
