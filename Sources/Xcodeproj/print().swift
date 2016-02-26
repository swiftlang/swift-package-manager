/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

public func print(srcroot srcroot: String, modules: [SwiftModule], products _: [Product], printer write: (String) -> Void) {

    let nontests = modules.filter{ !($0 is TestModule) }
    let tests = modules.filter{ $0 is TestModule }

    write("// !$*UTF8*$!")
    write("{")
    write("    archiveVersion = 1;")
    write("    classes = {")
    write("    };")
    write("    objectVersion = 46;")
    write("    objects = {")

    write("        REF00000000 = {")
    write("            isa = PBXProject;")
    write("            attributes = {LastUpgradeCheck = 9999;};")
    write("            buildConfigurationList = REF00000008;")
    write("            compatibilityVersion = 'Xcode 3.2';")
    write("            developmentRegion = English;")
    write("            hasScannedForEncodings = 0;")
    write("            knownRegions = (en);")
    write("            mainGroup = REF00000004;")
    write("            productRefGroup = REF00000017;")
    write("            projectDirPath = '';")
    write("            projectRoot = '';")
    write("            targets = (" + modules.map(productsGroupRef).joinWithSeparator(", ") + ");")
    write("        };")

////// root group
    write("        REF00000004 = {")
    write("            isa = PBXGroup;")
    write("            children = (REF0000000b, REF0000000c, REF00000017);")
    write("            sourceTree = '<group>';")
    write("        };")

////// modules group
    for module in modules {

        for (ref, path) in sourceFileRefs(module) {
            let path = Path(path).relative(to: srcroot)
            write("        \(ref) = {")
            write("            isa = PBXFileReference;")
            write("            lastKnownFileType = sourcecode.swift;")
            write("            name = \"\(path)\";")
            write("            sourceTree = '<group>';")
            write("        };")
        }

        write("        \(moduleGroupName(module)) = {")
        write("            isa = PBXGroup;")
        write("            name = \(module.name);")
        write("            path = '\(Path(module.sources.root).relative(to: srcroot))';")
        write("            sourceTree = '<group>';")
        write("            children = (" + sourceFileRefs(module).map{$0.0}.joinWithSeparator(", ") + ");")
        write("        };")

        let deps = module.dependencies.map{ dependencyRef(module: module, dep: $0) }.joinWithSeparator(", ")

        write("        \(productsGroupRef(module)) = {")
        write("            isa = PBXNativeTarget;")
        write("            buildConfigurationList = \(productBuildConfigurationList(module));")
        write("            buildPhases = (\(productBuildPhase(module)), \(linkBuildPhase(module: module)));")
        write("            buildRules = ();")
        write("            dependencies = (\(deps));")
        write("            name = \(module.name);")
        write("            productName = \(module.c99name);")
        write("            productReference = \(productRef(module));")
        write("            productType = '\(module.type)';")
        write("        };")
        write("        \(productRef(module)) = {")
        write("            isa = PBXFileReference;")
        write("            explicitFileType = 'compiled.mach-o.\(module.explicitFileType)';")
        write("            path = '\(module.productPath)';")
        write("            sourceTree = BUILT_PRODUCTS_DIR;")
        write("        };")

        for (ref1, ref2) in sourcesBuildPhaseFileRefs(module) + [(productRef(module), productBuildPhaseFileRef(module))] {
            write("        \(ref2) = {")
            write("            isa = PBXBuildFile;")
            write("            fileRef = \(ref1);")
            write("        };")
        }

        write("        \(productBuildPhase(module)) = {")
        write("            isa = PBXSourcesBuildPhase;")
        write("            buildActionMask = 2147483647;")
        write("            files = (\(sourcesBuildPhaseFileRefs(module).map{$1}.joinWithSeparator(", ")));")
        write("            runOnlyForDeploymentPostprocessing = 0;")
        write("        };")

        write("        \(productBuildConfigurationList(module)) = {")
        write("            isa = XCConfigurationList;")
        write("            buildConfigurations = (\(productBuildConfiguration(module)));")
        write("            defaultConfigurationIsVisible = 0;")
        write("            defaultConfigurationName = Debug;")
        write("        };")

        var buildSettings = "PRODUCT_NAME = '$(TARGET_NAME)';"

        if module is TestModule {
            buildSettings += " EMBEDDED_CONTENT_CONTAINS_SWIFT = YES;"
        } else if module.isLibrary {
            buildSettings += " DYLIB_INSTALL_NAME_BASE = '$(CONFIGURATION_BUILD_DIR)'; SWIFT_FORCE_STATIC_LINK_STDLIB = YES;"
        } else {
            buildSettings += " SWIFT_FORCE_STATIC_LINK_STDLIB = YES;"
        }

        //TODO probably should be a build option
        //        if !module.isLibrary {
//            buildSettings += " SWIFT_FORCE_STATIC_LINK_STDLIB = YES;"
//        }

        write("        \(productBuildConfiguration(module)) = {")
        write("            isa = XCBuildConfiguration;")
        write("            buildSettings = { \(buildSettings) };")
        write("            name = Debug;")
        write("        };")

        for dep in module.recursiveDependencies {
            write("        \(dependencyRef(module: module, dep: dep)) = {")
            write("            isa = PBXTargetDependency;")
            write("            target = \(productsGroupRef(dep));")
            write("            targetProxy = \(dependencyTargetProxyRef(module: module, dep: dep));")
            write("        };")

            write("        \(dependencyTargetProxyRef(module: module, dep: dep)) = {")
            write("            isa = PBXContainerItemProxy;")
            write("            containerPortal = REF00000000;")
            write("            proxyType = 1;")
            write("            remoteGlobalIDString = \(productsGroupRef(dep));")
            write("            remoteInfo = \(dep.c99name);")
            write("        };")

            let files = module.recursiveDependencies.map(productBuildPhaseFileRef).joinWithSeparator(", ")

            write("        \(linkBuildPhase(module: module)) = {")
            write("            isa = PBXFrameworksBuildPhase;")
            write("            buildActionMask = 2147483647;")
            write("            files = (\(files));")
            write("            runOnlyForDeploymentPostprocessing = 0;")
            write("        };")
        }
    }

////// sources group
    write("        REF0000000b = {")
    write("            isa = PBXGroup;")
    write("            children = (" + nontests.map(moduleGroupName).joinWithSeparator(", ") + ");")
    write("            name = Sources;")
    write("            sourceTree = '<group>';")
    write("        };")

////// sources group
    write("        REF0000000c = {")
    write("            isa = PBXGroup;")
    write("            children = (" + tests.map(moduleGroupName).joinWithSeparator(", ") + ");")
    write("            name = Tests;")
    write("            sourceTree = '<group>';")
    write("        };")

////// products group
    write("        REF00000017 = {")
    write("            isa = PBXGroup;")
    write("            children = (" + modules.map(productRef).joinWithSeparator(", ") + ");")
    write("            name = Products;")
    write("            sourceTree = '<group>';")
    write("        };")

////// build configuration
    write("        REF00000003 = {")
    write("            isa = XCBuildConfiguration;")
    write("            buildSettings = {};")
    write("            name = Debug;")
    write("        };")
    write("        REF00000008 = {")
    write("            isa = XCConfigurationList;")
    write("            buildConfigurations = (REF00000003);")
    write("            defaultConfigurationIsVisible = 0;")
    write("            defaultConfigurationName = Debug;")
    write("        };")
    write("    };")
    write("    rootObject = REF00000000;")
    write("}")
}

func productRef(module: Module) -> String {
    return "ProductModule\(module.c99name)"
}

func productsGroupRef(module: Module) -> String {
    return "Product\(module.c99name)"
}

func productBuildPhase(module: Module) -> String {
    return "ProductBuildPhase\(module.c99name)"
}

func productBuildConfigurationList(module: Module) -> String {
    return "ProductBuildConfigurationList\(module.c99name)"
}

func productBuildConfiguration(module: Module) -> String {
    return "ProductBuildConfiguration\(module.c99name)"
}

func sourceFileRefs(module: SwiftModule) -> [(String, String)] {
    let prefix = module.c99name

    return module.sources.relativePaths.map {
        return ("\(prefix)\($0.hashValue)", $0)
    }
}

func sourcesBuildPhaseFileRefs(module: SwiftModule) -> [(String, String)] {
    return sourceFileRefs(module).map{ ($0.0, "BuildPhaseFileRef\($0.0)") }
}

func productBuildPhaseFileRef(module: Module) -> String {
    return "ProductBuildPhaseFileRef\(module.c99name)"
}

func moduleGroupName(module: Module) -> String {
    return "Group\(module.c99name)"
}

func dependencyRef(module module: Module, dep: Module) -> String {
    return "Dep\(module.c99name)For\(dep.c99name)"
}

func dependencyTargetProxyRef(module module: Module, dep: Module) -> String {
    return "TargetProxyDep\(module.c99name)For\(dep.c99name)"
}

func linkBuildPhase(module module: Module) -> String {
    return "LinkBuildPhase\(module.c99name)"
}

extension SwiftModule {
    var type: String {
        if self is TestModule {
            return "com.apple.product-type.bundle.unit-test"
        } else if isLibrary {
            return "com.apple.product-type.library.dynamic"
        } else {
            return "com.apple.product-type.tool"
        }
    }

    var explicitFileType: String {
        if self is TestModule {
            return "wrapper.cfbundle"
        } else if isLibrary {
            return "dylib"
        } else {
            return "executable"
        }
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
}
