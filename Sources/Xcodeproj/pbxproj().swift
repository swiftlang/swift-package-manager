/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import POSIX
import PackageGraph
import PackageModel
import Utility


// FIXME: escaping


public func pbxproj(srcroot: AbsolutePath, projectRoot: AbsolutePath, xcodeprojPath: AbsolutePath, graph: PackageGraph, directoryReferences: [AbsolutePath], options: XcodeprojOptions, printer print: (String) -> Void) throws {
    // FIXME: Push this lower.
    let modules = graph.modules.filter{ $0.type != .systemModule }
    let externalModules = graph.externalModules.filter{ $0.type != .systemModule }

    // let rootModulesSet = Set(modules).subtract(Set(externalModules))
    let rootModulesSet = modules
    let nonTestRootModules = rootModulesSet.filter{ !$0.isTest }

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
    let packageSwift = fileRef(inProjectRoot: RelativePath("Package.swift"), srcroot: srcroot)
    print("        \(packageSwift.refId) = {")
    print("            isa = PBXFileReference;")
    print("            lastKnownFileType = sourcecode.swift;")
    print("            path = '\(packageSwift.path.relative(to: projectRoot).asString)';")
    print("            sourceTree = '<group>';")
    print("        };")

////// Reference directories

    var folderRefs = ""
    for directoryReference in directoryReferences {
        let folderRef = fileRef(inProjectRoot: directoryReference.relative(to: srcroot), srcroot: srcroot)
        folderRefs.append("\(folderRef.refId),")
        print("        \(folderRef.refId) = {")
        print("            isa = PBXFileReference;")
        print("            lastKnownFileType = folder;")
        print("            name = '\(directoryReference.basename)';")
        print("            path = '\(folderRef.path.relative(to: projectRoot).asString)';")
        print("            sourceTree = '<group>';")
        print("        };")
    }

////// root group
    print("        \(rootGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (\(packageSwift.refId), \(configsGroupReference), \(sourcesGroupReference), \(folderRefs) \(dependenciesGroupReference), \(testsGroupReference), \(productsGroupReference));")
    print("            sourceTree = '<group>';")
    print("        };")

////// modules group
    for module in modules {
        // Base directory for source files belonging to the module.
        let moduleRoot = module.sources.root

        // Contruct an array of (refId, path, bflId) tuples for all the source files in the model.  The reference id is for the PBXFileReference in the group hierarchy, and the build file id is for the PBXBuildFile in the CompileSources build phase.
        let sourceFileRefs = fileRefs(forModuleSources: module, srcroot: srcroot)

        // Hash of AbsolutePath of a group and reference id's of its children.
        // Children can be either a source file or a nested group
        var groupsChildren = [AbsolutePath: OrderedSet<String>]()

        // reference id's of immediate children of this module group.
        var topLevelRefs  = OrderedSet<String>()

        // the contents of the “Project Navigator” group for this module
        for fileRef in sourceFileRefs {
            let path = fileRef.path.relative(to: moduleRoot)
            print("        \(fileRef.refId) = {")
            print("            name = '\(fileRef.path.basename)';")
            print("            isa = PBXFileReference;")
            print("            lastKnownFileType = \(module.fileType(forSource: path));")
            print("            path = '\(fileRef.path.relative(to: srcroot).asString)';")
            print("            sourceTree = '<group>';")
            print("        };")

            // This source file is immediate children of module directory, ie., no nested folders
            if path.dirname == "." {
                topLevelRefs.append(fileRef.refId)
                continue
            }


            // Generate paths as follows:
            // Example:
            //    input: "MyModule/Foo/foo.swift"
            //   output: ["MyModule/Foo",
            //            "MyModule"]
            //
            let paths = [AbsolutePath](sequence(first: fileRef.path.parentDirectory, next: { path in
                let parent = path.parentDirectory
                return parent == moduleRoot ? nil : parent
            }))

            guard let parentGroupPath = paths.last else {
                fatalError("The source file: \(path.basename) is expected to be in a nested group")
            }


            topLevelRefs.append(parentGroupPath.groupReference(srcroot: srcroot))

            // Calculate children for each group.
            //
            // `paths` contains breadcrumbs paths as seen from the file.
            //
            // Ex:
            //   for source file: "MyModule/Foo/Bar/baz.swift"
            //   `paths` will contain: ["MyModule/Foo/Bar", "MyModule/Foo", "MyModule"]
            //                               paths[0]           path[1]       path[2]
            //
            //   So, the file, baz.swift, will be the child of paths[0],
            //                  paths[0], will be the child of paths[1],
            //                  paths[1], will be the child of paths[2], etc.,
            var currentChildren = fileRef.refId
            for path in paths {
                var children = groupsChildren[path] ?? OrderedSet<String>()
                children.append(currentChildren)
                groupsChildren[path] = children

                currentChildren = path.groupReference(srcroot: srcroot)
            }
        }

        // Create nested groups under this module.
        for (path, children) in groupsChildren {
            print("        \(path.groupReference(srcroot: srcroot)) = {")
            print("            isa = PBXGroup;")
            print("            name = '\(path.basename)';")
            print("            sourceTree = '<group>';")
            print("            children = (" + children.joined(separator: ", ") + ");")
            print("        };")
        }

        // the “Project Navigator” group for this module
        print("        \(module.groupReference) = {")
        print("            isa = PBXGroup;")
        print("            name = '\(module.name)';")
        print("            sourceTree = '<group>';")
        print("            children = (" + topLevelRefs.joined(separator: ", ") + ");")
        print("        };")


        // the target reference for this module’s product
        print("        \(module.targetReference) = {")
        print("            isa = PBXNativeTarget;")
        print("            buildConfigurationList = \(module.configurationListReference);")

        print("            buildPhases = (")
        // Add a shell script phase for clang module libraries for SR-2465.
        if module.isClangModuleLibrary {
            print("\(module.shellScriptPhaseReference), ")
        }
        print("\(module.compilePhaseReference), \(module.linkPhaseReference));")

        print("            buildRules = ();")
        print("            dependencies = (\(module.nativeTargetDependencies));")
        print("            name = '\(module.name)';")
        print("            productName = \(module.c99name);")
        print("            productReference = \(module.productReference);")
        print("            productType = '\(module.productType)';")
        print("        };")

        // the product file reference
        print("        \(module.productReference) = {")
        print("            isa = PBXFileReference;")
        print("            explicitFileType = '\(module.explicitFileType)';")
        print("            path = '\(module.productPath.asString)';")
        print("            sourceTree = BUILT_PRODUCTS_DIR;")
        print("        };")

        // shell script build phase.
        if module.isClangModuleLibrary {
            print("        \(module.shellScriptPhaseReference) = {")
            print("            isa = PBXShellScriptBuildPhase;")
            print("            shellPath = /bin/sh;")
            print("            shellScript = \"mkdir -p \\\"$PROJECT_TEMP_DIR/SymlinkLibs\\\"\nln -sf \\\"$BUILT_PRODUCTS_DIR/$EXECUTABLE_PATH\\\" \\\"$PROJECT_TEMP_DIR/SymlinkLibs/lib$EXECUTABLE_NAME.dylib\\\"\";")
            print("            runOnlyForDeploymentPostprocessing = 0;")
            print("        };")
        }

        // sources build phase
        print("        \(module.compilePhaseReference) = {")
        print("            isa = PBXSourcesBuildPhase;")
        print("            files = (\(sourceFileRefs.map{ $0.bflId }.joined(separator: ", ")));")
        print("            runOnlyForDeploymentPostprocessing = 0;")
        print("        };")

        // the fileRefs for the children in the build phases
        for fileRef in sourceFileRefs {
            print("        \(fileRef.bflId) = {")
            print("            isa = PBXBuildFile;")
            print("            fileRef = \(fileRef.refId);")
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
        print("            buildSettings = \(try module.getDebugBuildSettings(options, xcodeProjectPath: xcodeprojPath))")
        print("            name = Debug;")
        print("        };")
        print("        \(module.releaseConfigurationReference) = {")
        print("            isa = XCBuildConfiguration;")
        print("            buildSettings = \(try module.getReleaseBuildSettings(options, xcodeProjectPath: xcodeprojPath))")
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
    let projectXCConfig = fileRef(inProjectRoot: RelativePath("\(xcodeprojPath.basename)/Configs/Project.xcconfig"), srcroot: srcroot)
    try makeDirectories(projectXCConfig.path.parentDirectory)
    try open(projectXCConfig.path) { print in
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
        if !options.flags.cCompilerFlags.isEmpty {
            print("OTHER_CFLAGS = \(options.flags.cCompilerFlags.joined(separator: " "))")
        }
        if !options.flags.linkerFlags.isEmpty {
            print("OTHER_LDFLAGS = \(options.flags.linkerFlags.joined(separator: " "))")
        }
        print("OTHER_SWIFT_FLAGS = \((options.flags.swiftCompilerFlags+["-DXcode"]).joined(separator: " "))")
        
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
            print("\n#include \"\(path.asString)\"")
        }
    }
    let debugXCConfig = fileRef(inProjectRoot: RelativePath("\(xcodeprojPath.basename)/Configs/Debug.xcconfig"), srcroot: srcroot)
    try open(debugXCConfig.path) { print in
        print("#include \"Project.xcconfig\"")
        print("COPY_PHASE_STRIP = NO")
        print("DEBUG_INFORMATION_FORMAT = dwarf")
        print("ENABLE_NS_ASSERTIONS = YES")
        print("GCC_OPTIMIZATION_LEVEL = 0")
        print("ONLY_ACTIVE_ARCH = YES")
        print("SWIFT_OPTIMIZATION_LEVEL = -Onone")
    }
    let releaseXCConfig = fileRef(inProjectRoot: RelativePath("\(xcodeprojPath.basename)/Configs/Release.xcconfig"), srcroot: srcroot)
    try open(releaseXCConfig.path) { print in
        print("#include \"Project.xcconfig\"")
        print("DEBUG_INFORMATION_FORMAT = dwarf-with-dsym")
        print("GCC_OPTIMIZATION_LEVEL = s")
        print("SWIFT_OPTIMIZATION_LEVEL = -O")
        print("COPY_PHASE_STRIP = YES")
    }

    var configs = [projectXCConfig, debugXCConfig, releaseXCConfig]
    if let path = options.xcconfigOverrides {
        configs.append(fileRef(inProjectRoot: path.relative(to: srcroot), srcroot: srcroot))
    }    
    for configInfo in configs {
        print("        \(configInfo.refId) = {")
        print("            isa = PBXFileReference;")
        print("            lastKnownFileType = text.xcconfig;")
        print("            path = '\(configInfo.path.relative(to: projectRoot).asString)';")
        print("            sourceTree = '<group>';")
        print("        };")
    }
    
    print("        \(configsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + configs.map{ $0.refId }.joined(separator: ", ") + ");")
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
    let tests = modules.filter{ $0.isTest }
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
    productReferences += modules.flatMap { !$0.isTest ? $0.productReference : nil }

    print("        \(productsGroupReference) = {")
    print("            isa = PBXGroup;")
    print("            children = (" + productReferences.joined(separator: ", ") + ");")
    print("            name = Products;")
    print("            sourceTree = '<group>';")
    print("        };")

////// primary build configurations
    print("        \(rootDebugBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            baseConfigurationReference = \(debugXCConfig.0);")
    print("            buildSettings = {};")
    print("            name = Debug;")
    print("        };")
    print("        \(rootReleaseBuildConfigurationReference) = {")
    print("            isa = XCBuildConfiguration;")
    print("            baseConfigurationReference = \(releaseXCConfig.0);")
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

extension AbsolutePath {
    func groupReference(srcroot base: AbsolutePath) -> String {
        return "__Group_" + relative(to: base).asString
    }
}

extension Module {
    var blueprintIdentifier: String {
        return targetReference
    }

    var buildableName: String {
        return productName
    }

    var blueprintName: String {
        return name
    }
}

private extension SupportedLanguageExtension {
    var xcodeFileType: String {
        switch self {
        case .c:
            return "sourcecode.c.c"
        case .m:
            return "sourcecode.c.objc"
        case .cxx, .cc, .cpp:
            return "sourcecode.cpp.cpp"
        case .mm:
            return "sourcecode.cpp.objcpp"
        case .swift:
            return "sourcecode.swift"
        }
    }
}

private extension Module {

    var isClangModuleLibrary: Bool {
        if case let clangModule as ClangModule = self, clangModule.type == .library {
            return true
        }
        return false
    }

    func fileType(forSource source: RelativePath) -> String {
        switch self {
        case is SwiftModule:
            // SwiftModules only has one type of source so just always return this.
            return SupportedLanguageExtension.swift.xcodeFileType

        case is ClangModule:
            guard let suffix = source.suffix else {
                fatalError("Source \(source) doesn't have an extension in ClangModule \(name)")
            }
            // Suffix includes `.` so drop it.
            assert(suffix.hasPrefix("."))
            let fileExtension = String(suffix.characters.dropFirst())
            guard let ext = SupportedLanguageExtension(rawValue: fileExtension) else {
                fatalError("Unknown source extension \(source) in ClangModule \(name)")
            }
            return ext.xcodeFileType

        default:
            fatalError("unexpected module type")
        }
    }
}
