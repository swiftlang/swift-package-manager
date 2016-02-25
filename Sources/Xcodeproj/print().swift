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

    let modules = modules.filter{ !($0 is TestModule) }

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
    write("            children = (")
    write("                REF0000000b,")
    write("                REF00000017,")
    write("            );")
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
        let type = module.isLibrary ? "com.apple.product-type.library.dynamic" : "com.apple.product-type.tool"

        write("        \(productsGroupRef(module)) = {")
        write("            isa = PBXNativeTarget;")
        write("            buildConfigurationList = \(productBuildConfigurationList(module));")
        write("            buildPhases = (\(productBuildPhase(module)), \(linkBuildPhase(module: module)));")
        write("            buildRules = ();")
        write("            dependencies = (\(deps));")
        write("            name = \(module.name);")
        write("            productName = \(module.c99name);")
        write("            productReference = \(productRef(module));")
        write("            productType = '\(type)';")
        write("        };")

        let path = module.isLibrary ? "\(module.c99name).dylib" : "'\(module.name)'"
        let type2 = module.isLibrary ? "dylib" : "executable"

        write("        \(productRef(module)) = {")
        write("            isa = PBXFileReference;")
        write("            explicitFileType = 'compiled.mach-o.\(type2)';")
        write("            path = \(path);")
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

        let buildSettings = "PRODUCT_NAME = '$(TARGET_NAME)';"

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

    write("        REF0000000b = {")
    write("            isa = PBXGroup;")
    write("            children = (" + modules.map(moduleGroupName).joinWithSeparator(", ") + ");")
    write("            name = Sources;")
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
