/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import PackageModel
import Utility
import struct Basic.RelativePath

// FIXME: escaping

public func pbxproj(srcroot: String, projectRoot: String, xcodeprojPath: String, modules: [XcodeModuleProtocol], externalModules: [XcodeModuleProtocol], products _: [Product], options: XcodeprojOptions, printer print: (String) -> Void) throws {
    // let rootModulesSet = Set(modules).subtract(Set(externalModules))
    let rootModulesSet = modules
    let nonTestRootModules = rootModulesSet.filter{ !$0.isTest }
    let (tests, nonTests) = modules.partition{ $0.isTest }

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
    print("            path = '\(Path(packageSwift.2).relative(to: projectRoot))';")
    print("            sourceTree = '<group>';")
    print("        };")

////// root group
    print("        \(rootGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (\(packageSwift.0), \(configsGroupReference), \(sourcesGroupReference), \(dependenciesGroupReference), \(testsGroupReference), \(productsGroupReference));")
    print("            sourceTree = '<group>';")
    print("        };")

////// modules group
    for module in modules {

        let sourceFileRefPaths = fileRefs(forModuleSources: module, srcroot: srcroot)
        var sourceRefs = sourceFileRefPaths.map{$0.0}

        ////// Info.plist file reference if this a framework target
        if module.isLibrary {
            let (ref, path, name) = fileRef(ofInfoPlistFor: module, inDirectory: xcodeprojPath)
            print("        \(ref) = {")
            print("            isa = PBXFileReference;")
            print("            lastKnownFileType = text.plist.xml;")
            print("            name = '\(name)';")
            print("            path = '\(Path(path).relative(to: projectRoot))';")
            print("            sourceTree = SOURCE_ROOT;")
            print("        };")

            sourceRefs.append(ref)
        }


        // the “Project Navigator” group for this module
        print("        \(module.groupReference) = {")
        print("            isa = PBXGroup;")
        print("            name = \(module.name);")
        print("            path = '\(Path(module.sources.root).relative(to: projectRoot))';")
        print("            sourceTree = '<group>';")
        print("            children = (" + sourceRefs.joined(separator: ", ") + ");")
        print("        };")

        // the contents of the “Project Navigator” group for this module
        for (ref, path) in sourceFileRefPaths {
            print("        \(ref) = {")
            print("            isa = PBXFileReference;")
            print("            lastKnownFileType = \(module.fileType(forSource: RelativePath(path)));")
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
        print("            productType = '\(module.productType)';")
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

        // the fileRefs for the children in the build phases
        for (ref1, ref2) in fileRefs(forCompilePhaseSourcesInModule: module, srcroot: srcroot) {
            print("        \(ref2) = {")
            print("            isa = PBXBuildFile;")
            print("            fileRef = \(ref1);")
            print("        };")
        }

        // link build phase
        let linkPhaseFileRefs = module.linkPhaseFileRefs
        print("        \(module.linkPhaseReference) = {")
        print("            isa = PBXFrameworksBuildPhase;")
        print("            files = (\(linkPhaseFileRefs.map{ $0.fileRef }.joined(separator: ", ")));")
        print("            runOnlyForDeploymentPostprocessing = 0;")
        print("        };")
        for item in linkPhaseFileRefs {
            print("        \(item.fileRef) = {")
            print("            isa = PBXBuildFile;")
            print("            fileRef = \(item.dependency.productReference);")
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
        print("            buildSettings = { \(try module.getDebugBuildSettings(options, xcodeProjectPath: xcodeprojPath)) };")
        print("            name = Debug;")
        print("        };")
        print("        \(module.releaseConfigurationReference) = {")
        print("            isa = XCBuildConfiguration;")
        print("            buildSettings = { \(try module.getReleaseBuildSettings(options, xcodeProjectPath: xcodeprojPath)) };")
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

////// “Configs” group
    
    // The project-level xcconfig files.
    //
    // FIXME: Generate these into a sane path.
    let projectXCConfig = fileRef(inProjectRoot: Path.join(xcodeprojPath.basename, "Configs", "Project.xcconfig"), srcroot: Path.join(srcroot, projectRoot))
    try Utility.makeDirectories(projectXCConfig.2.parentDirectory)
    try open(projectXCConfig.2) { print in
        // Set the standard PRODUCT_NAME.
        print("PRODUCT_NAME = $(TARGET_NAME)")
        
        // Set SUPPORTED_PLATFORMS to all platforms.
        //
        // The goal here is to define targets which *can be* built for any
        // platform (although some might not work correctly). It is then up to
        // the integrating project to only set these targets up as dependencies
        // where appropriate.
        let supportedPlatforms = [
            "macosx",
            "iphoneos", "iphonesimulator",
            "appletvos", "appletvsimulator",
            "watchos", "watchsimulator"]
        print("SUPPORTED_PLATFORMS = \(supportedPlatforms.joined(separator: " "))")

        // Set a conservative default deployment target.
        //
        // We currently *must* do this for SwiftPM to be able to self-host in
        // Xcode (otherwise, the PackageDescription library will be incompatible
        // with the default deployment target we pass when building).
        //
        // FIXME: Eventually there should be a way for the project using Xcode
        // generation to have control over this.
        print("MACOSX_DEPLOYMENT_TARGET = 10.10")
        
        // Default to @rpath-based install names.
        //
        // The expectation is that the application or executable consuming these
        // products will need to establish the appropriate runpath search paths
        // so that all the products can be found in a relative manner.
        print("DYLIB_INSTALL_NAME_BASE = @rpath")

        // Propagate any user provided build flag overrides.
        //
        // FIXME: Need to get quoting correct here.
        if !options.Xcc.isEmpty {
            print("OTHER_CFLAGS = \(options.Xcc.joined(separator: " "))")
        }
        if !options.Xld.isEmpty {
            print("OTHER_LDFLAGS = \(options.Xld.joined(separator: " "))")
        }
        print("OTHER_SWIFT_FLAGS = \((options.Xswiftc+["-DXcode"]).joined(separator: " "))")
        
        // Prevents Xcode project upgrade warnings.
        print("COMBINE_HIDPI_IMAGES = YES")

        // Always disable use of headermaps.
        //
        // The semantics of the build should be explicitly defined by the
        // project structure, we don't want any additional behaviors not shared
        // with `swift build`.
        print("USE_HEADERMAP = NO")

        // If the user provided an overriding xcconfig path, include it here.
        if let path = options.xcconfigOverrides {
            print("\n#include \"\(path)\"")
        }
    }
    let configs = [projectXCConfig]
    for configInfo in configs {
        print("        \(configInfo.0) = {")
        print("            isa = PBXFileReference;")
        print("            lastKnownFileType = text.xcconfig;")
        print("            name = '\(configInfo.1.basename)';")
        print("            path = '\(Path(configInfo.2).relative(to: projectRoot))';")
        print("            sourceTree = '<group>';")
        print("        };")
    }
    
    print("        \(configsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + configs.map{ $0.0 }.joined(separator: ", ") + ");")
    print("            name = Configs;")
    print("            sourceTree = '<group>';")
    print("        };")

////// “Sources” group
    print("        \(sourcesGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + nonTestRootModules.map{ $0.groupReference }.joined(separator: ", ") + ");")
    print("            name = Sources;")
    print("            sourceTree = '<group>';")
    print("        };")

    if !externalModules.isEmpty {
        ////// “Dependencies” group
        print("        \(dependenciesGroupReference) = {")
        print("            isa = PBXGroup;")
        print("            children = (" + externalModules.map{ $0.groupReference }.joined(separator: ", ") + ");")
        print("            name = Dependencies;")
        print("            sourceTree = '<group>';")
        print("        };")
    }

////// “Tests” group
    if !tests.isEmpty {
        print("        \(testsGroupReference) = {")
        print("            isa = PBXGroup;")
        print("            children = (" + tests.map{ $0.groupReference }.joined(separator: ", ") + ");")
        print("            name = Tests;")
        print("            sourceTree = '<group>';")
        print("        };")
    }

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
    print("            baseConfigurationReference = \(projectXCConfig.0);")
    print("            buildSettings = {};")
    print("            name = Debug;")
    print("        };")
    print("        \(rootReleaseBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            baseConfigurationReference = \(projectXCConfig.0);")
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
