/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageType
import Utility

public func print(package package: Package, modules: [SwiftModule], products _: [Product], printer write: (String) throws -> Void) rethrows {

    let srcroot = package.path
    let nontests = modules.filter{ !($0 is TestModule) }
    let tests = modules.filter{ $0 is TestModule }

    try write("// !$*UTF8*$!")
    try write("{")
    try write("    archiveVersion = 1;")
    try write("    classes = {};")
    try write("    objectVersion = 46;")
    try write("    objects = {")

    try write("        REF00000000 = {")
    try write("            isa = PBXProject;")
    try write("            attributes = {LastUpgradeCheck = 9999;};")
    try write("            buildConfigurationList = REF00000008;")
    try write("            compatibilityVersion = 'Xcode 3.2';")
    try write("            developmentRegion = English;")
    try write("            hasScannedForEncodings = 0;")
    try write("            knownRegions = (en);")
    try write("            mainGroup = REF00000004;")
    try write("            productRefGroup = REF00000017;")
    try write("            projectDirPath = '';")
    try write("            projectRoot = '';")
    try write("            targets = (" + modules.map(productsGroupRef).joinWithSeparator(", ") + ");")
    try write("        };")

////// root group
    try write("        REF00000004 = {")
    try write("            isa = PBXGroup;")
    try write("            children = (REF0000000b, REF0000000c, REF00000017);")
    try write("            sourceTree = '<group>';")
    try write("        };")

////// modules group
    for module in modules {

        // the group for the sources in this target
        try write("        \(moduleGroupName(module)) = {")
        try write("            isa = PBXGroup;")
        try write("            name = \(module.name);")
        try write("            path = '\(Path(module.sources.root).relative(to: srcroot))';")
        try write("            sourceTree = '<group>';")
        try write("            children = (" + sourceFileRefs(module).map{$0.0}.joinWithSeparator(", ") + ");")
        try write("        };")
        
        // the references to the sources in this target
        for (ref, path) in sourceFileRefs(module) {
            let path = Path(path).relative(to: srcroot)
            try write("        \(ref) = {")
            try write("            isa = PBXFileReference;")
            try write("            lastKnownFileType = sourcecode.swift;")
            try write("            name = \"\(path)\";")
            try write("            sourceTree = '<group>';")
            try write("        };")
        }

        // the target
        try write("        \(productsGroupRef(module)) = {")
        try write("            isa = PBXNativeTarget;")
        try write("            buildConfigurationList = \(productBuildConfigurationList(module));")
        try write("            buildPhases = (\(productBuildPhase(module)), \(linkBuildPhase(module: module)));")
        try write("            buildRules = ();")
        try write("            dependencies = (\(module.nativeTargetDependencies));")
        try write("            name = \(module.name);")
        try write("            productName = \(module.c99name);")
        try write("            productReference = \(productRef(module));")
        try write("            productType = '\(module.type)';")
        try write("        };")
        
        // the product file reference
        try write("        \(productRef(module)) = {")
        try write("            isa = PBXFileReference;")
        try write("            explicitFileType = 'compiled.mach-o.\(module.explicitFileType)';")
        try write("            path = '\(module.productPath)';")
        try write("            sourceTree = BUILT_PRODUCTS_DIR;")
        try write("        };")

        // sources build phase
        try write("        \(productBuildPhase(module)) = {")
        try write("            isa = PBXSourcesBuildPhase;")
        try write("            buildActionMask = 2147483647;")
        try write("            files = (\(sourcesBuildPhaseFileRefs(module).map{$1}.joinWithSeparator(", ")));")
        try write("            runOnlyForDeploymentPostprocessing = 0;")
        try write("        };")

        // the references to the sources in the sources build phase
        for (ref1, ref2) in sourcesBuildPhaseFileRefs(module) + [(productRef(module), productBuildPhaseFileRef(module))] {
            try write("        \(ref2) = {")
            try write("            isa = PBXBuildFile;")
            try write("            fileRef = \(ref1);")
            try write("        };")
        }
        
        // link build phase
        try write("        \(linkBuildPhase(module: module)) = {")
        try write("            isa = PBXFrameworksBuildPhase;")
        try write("            buildActionMask = 2147483647;")
        try write("            files = (\(module.linkBuildPhaseFiles));")
        try write("            runOnlyForDeploymentPostprocessing = 0;")
        try write("        };")

        // the target build configuration
        try write("        \(productBuildConfigurationList(module)) = {")
        try write("            isa = XCConfigurationList;")
        try write("            buildConfigurations = (\(productBuildConfiguration(module)));")
        try write("            defaultConfigurationIsVisible = 0;")
        try write("            defaultConfigurationName = Debug;")
        try write("        };")
        try write("        \(productBuildConfiguration(module)) = {")
        try write("            isa = XCBuildConfiguration;")
        try write("            buildSettings = { \(module.buildSettings) };")
        try write("            name = Debug;")
        try write("        };")
        //TODO ^^ probably can consolidate this into the three kinds
        //TODO we use rather than have one per module

        // targets that depend on this target use these
        try write("        \(targetDependency(module)) = {")
        try write("            isa = PBXTargetDependency;")
        try write("            target = \(productsGroupRef(module));")
        // try write("            targetProxy = \(targetDependencyProxy(module));")
        try write("        };")
        // try write("        \(targetDependencyProxy(module)) = {")
        // try write("            isa = PBXContainerItemProxy;")
        // try write("            containerPortal = REF00000000;")
        // try write("            proxyType = 1;")
        // try write("            remoteGlobalIDString = \(productsGroupRef(module));")
        // try write("            remoteInfo = \(module.c99name);")
        // try write("        };")
    }

////// “Sources” group
    try write("        REF0000000b = {")
    try write("            isa = PBXGroup;")
    try write("            children = (" + nontests.map(moduleGroupName).joinWithSeparator(", ") + ");")
    try write("            name = Sources;")
    try write("            sourceTree = '<group>';")
    try write("        };")

////// “Tests” group
    try write("        REF0000000c = {")
    try write("            isa = PBXGroup;")
    try write("            children = (" + tests.map(moduleGroupName).joinWithSeparator(", ") + ");")
    try write("            name = Tests;")
    try write("            sourceTree = '<group>';")
    try write("        };")

////// products group
    try write("        REF00000017 = {")
    try write("            isa = PBXGroup;")
    try write("            children = (" + modules.map(productRef).joinWithSeparator(", ") + ");")
    try write("            name = Products;")
    try write("            sourceTree = '<group>';")
    try write("        };")

////// build configuration
    try write("        REF00000003 = {")
    try write("            isa = XCBuildConfiguration;")
    try write("            buildSettings = {};")
    try write("            name = Debug;")
    try write("        };")
    try write("        REF00000008 = {")
    try write("            isa = XCConfigurationList;")
    try write("            buildConfigurations = (REF00000003);")
    try write("            defaultConfigurationIsVisible = 0;")
    try write("            defaultConfigurationName = Debug;")
    try write("        };")
    try write("    };")
    try write("    rootObject = REF00000000;")
    try write("}")
}
