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

public func pbxproj(srcroot: String, projectRoot: String, modules: [SwiftModule], externalModules: [SwiftModule], products _: [Product], printer print: (String) -> Void) {

    let rootModulesSet = Set(modules).subtract(Set(externalModules))
    let nonTestRootModules = rootModulesSet.filter{ !($0 is TestModule) }
    let (tests, nonTests) = modules.partition{ $0 is TestModule }

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

////// Package.swift file
    let packageSwift = fileRef(inProjectRoot: "Package.swift", srcroot: srcroot)
    print("        \(packageSwift.0) = {")
    print("            isa = PBXFileReference;")
    print("            lastKnownFileType = sourcecode.swift;")
    print("            name = '\(packageSwift.1)';")
    print("            path = '\(packageSwift.2)';")
    print("            sourceTree = '<group>';")
    print("        };")

////// root group
    print("        \(rootGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (\(packageSwift.0), \(sourcesGroupReference), \(dependenciesGroupReference), \(testsGroupReference), \(productsGroupReference));")
    print("            sourceTree = '<group>';")
    print("        };")

////// modules group
    for module in modules {

        // the “Project Navigator” group for this module
        print("        \(module.groupReference) = {")
        print("            isa = PBXGroup;")
        print("            name = \(module.name);")
        print("            path = '\(Path(module.sources.root).relative(to: projectRoot))';")
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
        print("            productType = '\(module.type)';")
        print("        };")

        // the product file reference
        print("        \(module.productReference) = {")
        print("            isa = PBXFileReference;")
        print("            explicitFileType = '\(module.explicitFileType)';")
        print("            path = '\(module.productPath)';")
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
        print("            buildConfigurations = (\(module.debugConfigurationReference), \(module.releaseConfigurationReference));")
        print("            defaultConfigurationIsVisible = 0;")
        print("            defaultConfigurationName = Debug;")
        print("        };")
        print("        \(module.debugConfigurationReference) = {")
        print("            isa = XCBuildConfiguration;")
        print("            buildSettings = { \(module.debugBuildSettings) };")
        print("            name = Debug;")
        print("        };")
        print("        \(module.releaseConfigurationReference) = {")
        print("            isa = XCBuildConfiguration;")
        print("            buildSettings = { \(module.releaseBuildSettings) };")
        print("            name = Release;")
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
    print("            children = (" + nonTestRootModules.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Sources;")
    print("            sourceTree = '<group>';")
    print("        };")

    ////// “Dependencies” group
    print("        \(dependenciesGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + externalModules.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Dependencies;")
    print("            sourceTree = '<group>';")
    print("        };")

////// “Tests” group
    print("        \(testsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + tests.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Tests;")
    print("            sourceTree = '<group>';")
    print("        };")
    
    var productReferences: [String] = []
    
    if !tests.isEmpty {
        ////// “Product/Tests” group
        print("       \(testProductsGroupReference) = {")
        print("            isa = PBXGroup;")
        print("            children = (" + tests.map{ $0.productReference }.joined(separator: ", ") + ");")
        print("            name = Tests;")
        print("            sourceTree = '<group>';")
        print("        };")

        productReferences = [testProductsGroupReference]
    }

////// “Products” group
    productReferences += nonTests.map { $0.productReference }

    print("        \(productsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + productReferences.joined(separator: ", ") + ");")
    print("            name = Products;")
    print("            sourceTree = '<group>';")
    print("        };")

////// primary build configurations
    print("        \(rootDebugBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            buildSettings = {};")
    print("            name = Debug;")
    print("        };")
    print("        \(rootReleaseBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            buildSettings = {};")
    print("            name = Release;")
    print("        };")
    print("        \(rootBuildConfigurationListReference) = {")
    print("            isa = XCConfigurationList;")
    print("            buildConfigurations = (\(rootDebugBuildConfigurationReference), \(rootReleaseBuildConfigurationReference));")
    print("            defaultConfigurationIsVisible = 0;")
    print("            defaultConfigurationName = Debug;")
    print("        };")
    print("    };")

////// done!
    print("}")
}
