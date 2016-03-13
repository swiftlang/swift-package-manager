/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


//TODO escaping


import PackageType
import Utility

public func pbxproj(package package: Package, modules: [SwiftModule], products _: [Product], printer print: (String) -> Void, productType: ProductBuildType) {

    let srcroot = package.path
    let nontests = modules.filter{ !($0 is TestModule) }
    let tests = modules.filter{ $0 is TestModule }

    print("// !$*UTF8*$!")
    print("{")
    print("    archiveVersion = 1;")
    print("    classes = {};")
    print("    objectVersion = 46;")
    print("    rootObject = \(rootObjectReference);")

    print("    objects = {")

////// root object, ie. the Project itself
    print("        \(rootObjectReference) = {")
    print("            isa = PBXProject;")
    print("            attributes = {LastUpgradeCheck = 9999;};")   // we're generated: don’t upgrade check
    print("            buildConfigurationList = \(rootBuildConfigurationListReference);")
    print("            compatibilityVersion = 'Xcode 3.2';")
    print("            developmentRegion = English;")
    print("            hasScannedForEncodings = 0;")
    print("            knownRegions = (en);")
    print("            mainGroup = \(rootGroupReference);")
    print("            productRefGroup = \(productsGroupReference);")
    print("            projectDirPath = '';")
    print("            projectRoot = '';")
    print("            targets = (" + modules.map{ $0.targetReference }.joined(separator: ", ") + ");")
    print("        };")

////// root group
    print("        \(rootGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (\(sourcesGroupReference), \(testsGroupReference), \(productsGroupReference));")
    print("            sourceTree = '<group>';")
    print("        };")

////// modules group
    for module in modules {

        // the “Project Navigator” group for this module
        print("        \(module.groupReference) = {")
        print("            isa = PBXGroup;")
        print("            name = \(module.name);")
        print("            path = '\(Path(module.sources.root).relative(to: srcroot))';")
        print("            sourceTree = '<group>';")
        print("            children = (" + fileRefs(forModuleSources: module, srcroot: srcroot).map{$0.0}.joined(separator: ", ") + ");")
        print("        };")

        // the contents of the “Project Navigator” group for this module
        for (ref, path) in fileRefs(forModuleSources: module, srcroot: srcroot) {
            print("        \(ref) = {")
            print("            isa = PBXFileReference;")
            print("            lastKnownFileType = sourcecode.swift;")
            print("            name = '\(Path(path).relative(to: module.sources.root))';")
            print("            sourceTree = '<group>';")
            print("        };")
        }

        // the target reference for this module’s product
        print("        \(module.targetReference) = {")
        print("            isa = PBXNativeTarget;")
        print("            buildConfigurationList = \(module.configurationListReference);")
        print("            buildPhases = (\(module.compilePhaseReference), \(module.linkPhaseReference));")
        print("            buildRules = ();")
        print("            dependencies = (\(module.nativeTargetDependencies));")
        print("            name = \(module.name);")
        print("            productName = \(module.c99name);")
        print("            productReference = \(module.productReference);")
        print("            productType = '\(module.productType(forType: productType))';")
        print("        };")

        // the product file reference
        print("        \(module.productReference) = {")
        print("            isa = PBXFileReference;")
        print("            explicitFileType = '\(module.explicitFileType(forType: productType))';")
        print("            path = '\(module.productPath(forType: productType))';")
        print("            sourceTree = BUILT_PRODUCTS_DIR;")
        print("        };")

        // sources build phase
        print("        \(module.compilePhaseReference) = {")
        print("            isa = PBXSourcesBuildPhase;")
        print("            files = (\(fileRefs(forCompilePhaseSourcesInModule: module, srcroot: srcroot).map{$1}.joined(separator: ", ")));")
        print("            runOnlyForDeploymentPostprocessing = 0;")
        print("        };")

        // link build phase
        print("        \(module.linkPhaseReference) = {")
        print("            isa = PBXFrameworksBuildPhase;")
        print("            files = (\(module.linkPhaseFileRefs));")
        print("            runOnlyForDeploymentPostprocessing = 0;")
        print("        };")

        // the fileRefs for the children in the build phases
        for (ref1, ref2) in fileRefs(forCompilePhaseSourcesInModule: module, srcroot: srcroot) + [(module.productReference, fileRef(forLinkPhaseChild: module))] {
            print("        \(ref2) = {")
            print("            isa = PBXBuildFile;")
            print("            fileRef = \(ref1);")
            print("        };")
        }

        // the target build configuration
        print("        \(module.configurationListReference) = {")
        print("            isa = XCConfigurationList;")
        print("            buildConfigurations = (\(module.configurationReference));")
        print("            defaultConfigurationIsVisible = 0;")
        print("            defaultConfigurationName = Debug;")
        print("        };")
        print("        \(module.configurationReference) = {")
        print("            isa = XCBuildConfiguration;")
        print("            buildSettings = { \(module.buildSettings) };")
        print("            name = Debug;")
        print("        };")

        //TODO ^^ probably can consolidate this into the three kinds
        //TODO we use rather than have one per module

        // targets that depend on this target use these
        print("        \(module.dependencyReference) = {")
        print("            isa = PBXTargetDependency;")
        print("            target = \(module.targetReference);")
        print("        };")
    }

////// “Sources” group
    print("        \(sourcesGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + nontests.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Sources;")
    print("            sourceTree = '<group>';")
    print("        };")

////// “Tests” group
    print("        \(testsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + tests.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Tests;")
    print("            sourceTree = '<group>';")
    print("        };")

////// “Products” group
    print("        \(productsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + modules.map{ $0.productReference }.joined(separator: ", ") + ");")
    print("            name = Products;")
    print("            sourceTree = '<group>';")
    print("        };")

////// primary build configurations
    print("        \(rootBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            buildSettings = {};")
    print("            name = Debug;")
    print("        };")
    print("        \(rootBuildConfigurationListReference) = {")
    print("            isa = XCConfigurationList;")
    print("            buildConfigurations = (\(rootBuildConfigurationReference));")
    print("            defaultConfigurationIsVisible = 0;")
    print("            defaultConfigurationName = Debug;")
    print("        };")
    print("    };")
    
////// done!
    print("}")
}
