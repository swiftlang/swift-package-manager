/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

//TODO our references should remain human readable, but they
// aren't unique enough, eg. if a module is called ProxyFoo then the TargetProxy for Foo will conflict with the Target for ProxyFoo

import PackageType
import Utility

public func print(package package: Package, modules: [SwiftModule], products _: [Product], printer write: (String) -> Void) {

    let srcroot = package.path
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
    write("            targets = (AggregateTarget, " + modules.map(productsGroupRef).joinWithSeparator(", ") + ");")
    write("        };")

////// root group
    write("        REF00000004 = {")
    write("            isa = PBXGroup;")
    write("            children = (REF0000000b, REF0000000c, REF00000017);")
    write("            sourceTree = '<group>';")
    write("        };")

////// modules group
    for module in modules {

        // the group for the sources in this target
        write("        \(moduleGroupName(module)) = {")
        write("            isa = PBXGroup;")
        write("            name = \(module.name);")
        write("            path = '\(Path(module.sources.root).relative(to: srcroot))';")
        write("            sourceTree = '<group>';")
        write("            children = (" + sourceFileRefs(module).map{$0.0}.joinWithSeparator(", ") + ");")
        write("        };")
        
        // the references to the sources in this target
        for (ref, path) in sourceFileRefs(module) {
            let path = Path(path).relative(to: srcroot)
            write("        \(ref) = {")
            write("            isa = PBXFileReference;")
            write("            lastKnownFileType = sourcecode.swift;")
            write("            name = \"\(path)\";")
            write("            sourceTree = '<group>';")
            write("        };")
        }

        // the target
        write("        \(productsGroupRef(module)) = {")
        write("            isa = PBXNativeTarget;")
        write("            buildConfigurationList = \(productBuildConfigurationList(module));")
        write("            buildPhases = (\(productBuildPhase(module)), \(linkBuildPhase(module: module)));")
        write("            buildRules = ();")
        write("            dependencies = (\(module.nativeTargetDependencies));")
        write("            name = \(module.name);")
        write("            productName = \(module.c99name);")
        write("            productReference = \(productRef(module));")
        write("            productType = '\(module.type)';")
        write("        };")
        
        // the product file reference
        write("        \(productRef(module)) = {")
        write("            isa = PBXFileReference;")
        write("            explicitFileType = 'compiled.mach-o.\(module.explicitFileType)';")
        write("            path = '\(module.productPath)';")
        write("            sourceTree = BUILT_PRODUCTS_DIR;")
        write("        };")

        // sources build phase
        write("        \(productBuildPhase(module)) = {")
        write("            isa = PBXSourcesBuildPhase;")
        write("            buildActionMask = 2147483647;")
        write("            files = (\(sourcesBuildPhaseFileRefs(module).map{$1}.joinWithSeparator(", ")));")
        write("            runOnlyForDeploymentPostprocessing = 0;")
        write("        };")

        // the references to the sources in the sources build phase
        for (ref1, ref2) in sourcesBuildPhaseFileRefs(module) + [(productRef(module), productBuildPhaseFileRef(module))] {
            write("        \(ref2) = {")
            write("            isa = PBXBuildFile;")
            write("            fileRef = \(ref1);")
            write("        };")
        }
        
        // link build phase
        write("        \(linkBuildPhase(module: module)) = {")
        write("            isa = PBXFrameworksBuildPhase;")
        write("            buildActionMask = 2147483647;")
        write("            files = (\(module.linkBuildPhaseFiles));")
        write("            runOnlyForDeploymentPostprocessing = 0;")
        write("        };")

        // the target build configuration
        write("        \(productBuildConfigurationList(module)) = {")
        write("            isa = XCConfigurationList;")
        write("            buildConfigurations = (\(productBuildConfiguration(module)));")
        write("            defaultConfigurationIsVisible = 0;")
        write("            defaultConfigurationName = Debug;")
        write("        };")
        write("        \(productBuildConfiguration(module)) = {")
        write("            isa = XCBuildConfiguration;")
        write("            buildSettings = { \(module.buildSettings) };")
        write("            name = Debug;")
        write("        };")
        //TODO ^^ probably can consolidate this into the three kinds
        //TODO we use rather than have one per module

        // targets that depend on this target use these
        write("        \(targetDependency(module)) = {")
        write("            isa = PBXTargetDependency;")
        write("            target = \(productsGroupRef(module));")
        // write("            targetProxy = \(targetDependencyProxy(module));")
        write("        };")
        // write("        \(targetDependencyProxy(module)) = {")
        // write("            isa = PBXContainerItemProxy;")
        // write("            containerPortal = REF00000000;")
        // write("            proxyType = 1;")
        // write("            remoteGlobalIDString = \(productsGroupRef(module));")
        // write("            remoteInfo = \(module.c99name);")
        // write("        };")
    }

////// “Sources” group
    write("        REF0000000b = {")
    write("            isa = PBXGroup;")
    write("            children = (" + nontests.map(moduleGroupName).joinWithSeparator(", ") + ");")
    write("            name = Sources;")
    write("            sourceTree = '<group>';")
    write("        };")

////// “Tests” group
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

///// aggregate target
    write("        AggregateTarget = {")
    write("            isa = PBXAggregateTarget;")
    write("            buildConfigurationList = REF0000001a;")
    write("            buildPhases = ();")
    write("            dependencies = (\(nontests.map(targetDependency).joinWithSeparator(", ")));")
    write("            name = _\(package.name);")  // HACK underscore puts it at the top
    write("            productName = WTF;")
    write("        };")
    write("        REF0000001a = {")
    write("                isa = XCConfigurationList;")
    write("                buildConfigurations = (")
    write("                    REF0000001b,")
    write("                );")
    write("                defaultConfigurationIsVisible = 0;")
    write("                defaultConfigurationName = Debug;")
    write("            };")
    write("            REF0000001b = {")
    write("                isa = XCBuildConfiguration;")
    write("                buildSettings = {")
    write("                    PRODUCT_NAME = '$(TARGET_NAME)';")
    write("                };")
    write("                name = Debug;")
    write("         };")

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

func targetDependency(module: Module) -> String {
    return "TargetDependency\(module.c99name)"
}

func targetDependencyProxy(module: Module) -> String {
    return "TargetDependencyProxy\(module.c99name)"
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
    
    var linkBuildPhaseFiles: String {
        return recursiveDependencies.map(productBuildPhaseFileRef).joinWithSeparator(", ")
    }
    
    var nativeTargetDependencies: String {
        return dependencies.map(targetDependency).joinWithSeparator(", ")
    }
    
    var buildSettings: String {
        var buildSettings = "PRODUCT_NAME = '$(TARGET_NAME)';"

        if self is TestModule {
            buildSettings += " EMBEDDED_CONTENT_CONTAINS_SWIFT = YES;"
            buildSettings += " LD_RUNPATH_SEARCH_PATHS = '@loader_path/../Frameworks';"
        } else if isLibrary {
            buildSettings += " ENABLE_TESTABILITY = YES;"
            buildSettings += " DYLIB_INSTALL_NAME_BASE = '$(CONFIGURATION_BUILD_DIR)';"
            buildSettings += " SWIFT_FORCE_STATIC_LINK_STDLIB = YES;"
        } else {
            buildSettings += " SWIFT_FORCE_STATIC_LINK_STDLIB = YES;"
        }

        return buildSettings
    }
}
