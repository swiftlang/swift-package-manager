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
import PackageLoading
import Utility

/// Errors encounter during Xcode project generation
public enum ProjectGenerationError: Swift.Error {
    /// The given xcconfig override file does not exist
    case xcconfigOverrideNotFound(path: AbsolutePath)
}

/// Generates the contents of the `project.pbxproj` for the package graph.  The
/// project file is generated with the assumption that it will be written to an
/// .xcodeproj wrapper at `xcodeprojPath` (this affects relative references to
/// ancillary files inside the wrapper).  Note that the root directory of the
/// sources is not necessarily related to this path; the source root directory
/// is the path of the root package in the package graph, independent of the
/// directory to which the .xcodeproj is being generated.
public func pbxproj(
        xcodeprojPath: AbsolutePath,
        graph: PackageGraph,
        extraDirs: [AbsolutePath],
        options: XcodeprojOptions,
        fileSystem: FileSystem = localFileSystem
    ) throws -> String {
    let project = try xcodeProject(xcodeprojPath: xcodeprojPath, graph: graph, extraDirs: extraDirs, options: options, fileSystem: fileSystem)
    // Serialize the project model we created to a plist, and return
    // its string description.
    return "// !$*UTF8*$!\n" + project.generatePlist().description
}

func xcodeProject(
    xcodeprojPath: AbsolutePath,
    graph: PackageGraph,
    extraDirs: [AbsolutePath],
    options: XcodeprojOptions,
    fileSystem: FileSystem
    ) throws -> Xcode.Project {
    
    // Create the project.
    let project = Xcode.Project()
    
    // Determine the source root directory (which is NOT necessarily related in
    // any way to `xcodeprojPath`, i.e. we cannot assume that the Xcode project
    // will be generated into to the source root directory).
    let sourceRootDir = graph.rootPackage.path
    
    // Set the project's notion of the source root directory to be a relative
    // path from the directory that contains the .xcodeproj to the source root
    // directory (note that those two directories might or might be the same).
    // The effect is to make any `projectDir`-relative path be relative to the
    // source root directory, i.e. the path of the root package.
    project.projectDir = sourceRootDir.relative(to: xcodeprojPath.parentDirectory).asString
    
    // Configure the project settings.
    let projectSettings = project.buildSettings
    
    // First of all, set a standard definition of `PROJECT_NAME`.
    projectSettings.common.PRODUCT_NAME = "$(TARGET_NAME)"
    
    // Set the SUPPORTED_PLATFORMS to all platforms.
    // FIXME: This doesn't seem correct, but was what the old project generation
    // code did, so for now we do so too.
    projectSettings.common.SUPPORTED_PLATFORMS = ["macosx", "iphoneos", "iphonesimulator", "appletvos", "appletvsimulator", "watchos", "watchsimulator"]

    // Set the default `SDKROOT` to the latest macOS SDK.
    projectSettings.common.SDKROOT = "macosx"

    // Set a conservative default deployment target.
    // FIXME: There needs to be some kind of control over this.  But currently
    // it is required to set this in order for SwiftPM to be able to self-host
    // in Xcode; otherwise, the PackageDescription library will be incompatible
    // with the default deployment target we pass when building.
    projectSettings.common.MACOSX_DEPLOYMENT_TARGET = "10.10"
    
    // Default to @rpath-based install names.  Any target that links against
    // these products will need to establish the appropriate runpath search
    // paths so that all the products can be found.
    projectSettings.common.DYLIB_INSTALL_NAME_BASE = "@rpath"
    
    // Add any additional compiler and linker flags the user has specified.
    if !options.flags.cCompilerFlags.isEmpty {
        projectSettings.common.OTHER_CFLAGS = options.flags.cCompilerFlags
    }
    if !options.flags.linkerFlags.isEmpty {
        projectSettings.common.OTHER_LDFLAGS = options.flags.linkerFlags
    }
    if !options.flags.swiftCompilerFlags.isEmpty {
        projectSettings.common.OTHER_SWIFT_FLAGS = options.flags.swiftCompilerFlags
    }
    
    // Also set the `Xcode` build preset in Swift to let code conditionalize on
    // being built in Xcode.
    projectSettings.common.OTHER_SWIFT_FLAGS += ["-DXcode"]
    
    // Prevent Xcode project upgrade warnings.
    projectSettings.common.COMBINE_HIDPI_IMAGES = "YES"
    
    // Set the Swift version to 3.0 (we'll need to make this dynamic), but for
    // now this is necessary.
    projectSettings.common.SWIFT_VERSION = "3.0"
    
    // Defined for regular `swift build` instantiations, so also should be defined here.
    projectSettings.common.SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SWIFT_PACKAGE"
    
    // Opt out of headermaps.  The semantics of the build should be explicitly
    // defined by the project structure, so that we don't get any additional
    // magic behavior that isn't present in `swift build`.
    projectSettings.common.USE_HEADERMAP = "NO"
    
    // Add some debug-specific settings.
    projectSettings.debug.COPY_PHASE_STRIP = "NO"
    projectSettings.debug.DEBUG_INFORMATION_FORMAT = "dwarf"
    projectSettings.debug.ENABLE_NS_ASSERTIONS = "YES"
    projectSettings.debug.GCC_OPTIMIZATION_LEVEL = "0"
    projectSettings.debug.ONLY_ACTIVE_ARCH = "YES"
    projectSettings.debug.SWIFT_OPTIMIZATION_LEVEL = "-Onone"
    
    // Add some release-specific settings.
    projectSettings.release.COPY_PHASE_STRIP = "YES"
    projectSettings.release.DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"
    projectSettings.release.GCC_OPTIMIZATION_LEVEL = "s"
    projectSettings.release.SWIFT_OPTIMIZATION_LEVEL = "-O"

    // Add a file reference for the package manifest itself.
    project.mainGroup.addFileReference(path: "Package.swift", fileType: "sourcecode.swift")
    
    // Add a group for the overriding .xcconfig file, if we have one.
    let xcconfigOverridesFileRef: Xcode.FileReference?
    if let xcconfigPath = options.xcconfigOverrides {
        // Verify that the xcconfig override file exists
        if !fileSystem.exists(xcconfigPath) {
            throw ProjectGenerationError.xcconfigOverrideNotFound(path: xcconfigPath)
        }

        // Create a "Configs" group whose path is the same as the project path.
        let xcconfigsGroup = project.mainGroup.addGroup(path: "", name: "Configs")
        
        // Create a file reference for the .xcconfig file (with a path relative
        // to the group).
        xcconfigOverridesFileRef = xcconfigsGroup.addFileReference(path: xcconfigPath.relative(to: sourceRootDir).asString, name: xcconfigPath.basename)
        
        // We don't assign the file reference as the xcconfig file reference of
        // the project's build settings, because if we do, the xcconfig cannot
        // override any of the default build settings at the project level.  So
        // we instead assign it to each target.
        
        // We may instead want to emit all build settings to separate .xcconfig
        // files that use `#include` to include the overriding .xcconfig file.
    }
    else {
        // Otherwise, we don't create an .xcconfig file reference.
        xcconfigOverridesFileRef = nil
    }
    
    // Add a `Sources` group, to which we'll add a subgroup for every regular
    // module.
    let sourcesGroup = project.mainGroup.addGroup(path: "Sources")
    
    // Add a `Tests` group, to which we'll add a subgroup for every test module.
    let testsGroup = project.mainGroup.addGroup(path: "Tests")
    
    // Add "blue folders" for all the other directories at the top level.
    for extraDir in extraDirs {
        project.mainGroup.addFileReference(path: extraDir.relative(to: sourceRootDir).asString, pathBase: .projectDir)
    }
    
    // Add a `Products` group, and set it as the project's product group.  This
    // is the group to which we'll add references to the outputs of the various
    // targets; these references will be added to the link phases.
    let productsGroup = project.mainGroup.addGroup(path: "", pathBase: .buildDir, name: "Products")
    project.productGroup = productsGroup
    
    // Determine the set of modules to generate in the project by excluding
    // any system modules.
    let modules = graph.modules.filter{ $0.type != .systemModule }
    
    // We'll need a mapping of modules to the corresponding targets.
    var modulesToTargets: [Module: Xcode.Target] = [:]
    
    // To avoid creating multiple groups for the same path, we keep a mapping
    // of the paths we've seen and the corresponding groups we've created.
    var srcPathsToGroups: [AbsolutePath: Xcode.Group] = [:]
    
    // Private helper function to make a group (or return an existing one) for
    // a particular path, including any intermediate groups that may be needed.
    func makeGroup(for path: AbsolutePath) -> Xcode.Group {
        // Check if we already have a group.
        if let group = srcPathsToGroups[path] {
            return group
        }
        // We don't, so create one, starting with the parent.
        let parentGroup = makeGroup(for: path.parentDirectory)
        let group = parentGroup.addGroup(path: path.basename)
        srcPathsToGroups[path] = group
        return group
    }
    
    // Add a mapping from the project dir to the main group, as a backstop for
    // any paths that get so far (doesn't happen in a standard package layout).
    srcPathsToGroups[sourceRootDir] = project.mainGroup
    
    // Go through all the modules, creating targets and adding file references
    // to the group tree (the specific top-level group under which they are
    // added depends on whether or not the module is a test module).
    for module in modules {
        // Determine the appropriate product type based on the kind of module.
        // FIXME: We should factor this out.
        let productType: Xcode.Target.ProductType
        if module.isTest {
            productType = .unitTest
        } else if module.isLibrary {
            productType = .framework
        } else {
            productType = .executable
        }
        
        // Create a target for the module.
        let target = project.addTarget(productType: productType, name: module.name)
        
        // Set the product name to the C99-mangled form of the module name.
        target.productName = module.c99name
        
        // Configure the target settings based on the module.  We set only the
        // minimum settings required, because anything we set on the target is
        // not overridable by the user-supplied .xcconfig file.
        let targetSettings = target.buildSettings
        
        // Set the target's base .xcconfig file to the user-supplied override
        // .xcconfig, if we have one.  This lets it override project settings.
        targetSettings.xcconfigFileRef = xcconfigOverridesFileRef

        targetSettings.common.TARGET_NAME = module.name
        
        let infoPlistFilePath = xcodeprojPath.appending(component: module.infoPlistFileName)
        targetSettings.common.INFOPLIST_FILE = infoPlistFilePath.relative(to: sourceRootDir).asString
        
        // Add default library search path to the directory where symlinks to
        // framework binaries will be put with name `lib<library-name>.dylib`
        // so that autolinking can proceed without providing another modulemap
        // for Xcode projects.
        // See: https://bugs.swift.org/browse/SR-2465
        if module.recursiveDependencies.first(where: { $0 is ClangModule }) != nil {
            targetSettings.common.LIBRARY_SEARCH_PATHS = ["$(PROJECT_TEMP_DIR)/SymlinkLibs/"]
        }
        
        if module.isTest {
            targetSettings.common.EMBEDDED_CONTENT_CONTAINS_SWIFT = "YES"
            targetSettings.common.LD_RUNPATH_SEARCH_PATHS = ["@loader_path/../Frameworks"]
        }
        else {
            // We currently force a search path to the toolchain, since we can't
            // establish an expected location for the Swift standard libraries.
            //
            // Note that this means that the built binaries are not suitable for
            // distribution, among other things.
            targetSettings.common.LD_RUNPATH_SEARCH_PATHS = ["$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"]
            if module.isLibrary {
                targetSettings.common.ENABLE_TESTABILITY = "YES"
                targetSettings.common.PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)"
                targetSettings.common.PRODUCT_MODULE_NAME = "$(TARGET_NAME:c99extidentifier)"
                targetSettings.common.PRODUCT_BUNDLE_IDENTIFIER = module.c99name
            }
            else {
                targetSettings.common.SWIFT_FORCE_STATIC_LINK_STDLIB = "NO"
                targetSettings.common.SWIFT_FORCE_DYNAMIC_LINK_STDLIB = "YES"
                
                targetSettings.common.LD_RUNPATH_SEARCH_PATHS += ["@executable_path"]
            }
        }
        
        if let pkgArgs = try? module.pkgConfigArgs() {
            targetSettings.common.OTHER_LDFLAGS = ["$(inherited)"] + pkgArgs.libs
            targetSettings.common.OTHER_SWIFT_FLAGS = ["$(inherited)"] + pkgArgs.cFlags
        }
        
        // Add header search paths for any C module on which we depend.
        var hdrInclPaths = ["$(inherited)"]
        for depModule in [module] + module.recursiveDependencies {
            // FIXME: Possibly factor this out into a separate protocol; the
            // idea would be that we would ask the module how it contributes
            // to the overall build environment for client modules, which can
            // affect search paths and other flags.  This should be done in a
            // way that allows SwiftPM to detect incompatibilities.
            switch depModule {
              case let cModule as CModule:  // System module
                hdrInclPaths.append(cModule.path.relative(to: sourceRootDir).asString)
              case let clangModule as ClangModule:
                hdrInclPaths.append(clangModule.includeDir.relative(to: sourceRootDir).asString)
              default:
                continue
            }
        }
        targetSettings.common.HEADER_SEARCH_PATHS = hdrInclPaths

        // Add framework search path to build settings.
        targetSettings.common.FRAMEWORK_SEARCH_PATHS = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]
        
        // Add a file reference for the target's product.
        let productRef = productsGroup.addFileReference(path: module.productPath.asString, pathBase: .buildDir)
        
        // Set that file reference as the target's product reference.
        target.productReference = productRef
        
        // Add a shell script build phase to create a symlink to the produced
        // library in a shared location so other modules can find it.
        if case let clangModule as ClangModule = module, clangModule.type == .library {
            let script = "mkdir -p \"${PROJECT_TEMP_DIR}/SymlinkLibs\"\n"
                       + "ln -sf \"${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}\" \"${PROJECT_TEMP_DIR}/SymlinkLibs/lib${EXECUTABLE_NAME}.dylib\"\n"
            target.addShellScriptBuildPhase(script: script)
        }
        
        // Add a compile build phase (which Xcode calls "Sources").
        let compilePhase = target.addSourcesBuildPhase()
        
        // We don't add dependencies yet — we do so in a separate pass, since
        // some dependencies might be on targets that we have not yet created.
        
        // We also don't add the link phase yet, since we'll do so at the same
        // time as we set up dependencies.
        
        // Record the target that we created for this module, for later passes.
        modulesToTargets[module] = target
        
        // Determine the top-level directory for source files of the module.
        let moduleRootDir = module.sources.root
        
        // Choose either `Sources` or `Tests` as the parent group.
        let moduleParentGroup = module.isTest ? testsGroup : sourcesGroup
        
        // Create a group for the module, and set its path to the module source
        // root.  We make it a top-level group even if it isn't in the package's
        // `Sources` directory (doesn't happen in a standard package layout).
        let moduleGroup = moduleParentGroup.addGroup(path: moduleRootDir.relative(to: sourceRootDir).asString, pathBase: .projectDir, name: module.name)
        
        // We add the group to the mapping, so that sources will find it.
        srcPathsToGroups[moduleRootDir] = moduleGroup
        
        // Go through the module source files.  As we do, we create groups for
        // any path components other than the last one.  We also add build files
        // to the compile phase of the target we created.
        for sourceFile in module.sources.paths {
            // Make (or find) a group for the directory.
            let group = makeGroup(for: sourceFile.parentDirectory)
            
            // Create a reference for the source file.  We don't set its file
            // type; rather, we let Xcode determine it based on the suffix.
            let srcFileRef = group.addFileReference(path: sourceFile.basename)
            
            // Also add the source file to the compile phase.
            compilePhase.addBuildFile(fileRef: srcFileRef)
        }

        // Add the `include` group for a libary C language target.
        if case let clangModule as ClangModule = module, clangModule.type == .library, fileSystem.isDirectory(clangModule.includeDir) {
            let includeDir = clangModule.includeDir
            let includeGroup = makeGroup(for: includeDir)
            // FIXME: Support C++ headers.
            for header in try walk(includeDir, fileSystem: fileSystem) where header.extension == "h" {
                let group = makeGroup(for: header.parentDirectory)
                group.addFileReference(path: header.basename)
            }

            // Generate a module map for ClangModule (if not provided by user) and
            // add to the build settings.
            targetSettings.common.DEFINES_MODULE = "YES"
            let moduleMapPath: AbsolutePath
            // If user provided the modulemap no need to generate.
            if fileSystem.isFile(clangModule.moduleMapPath) {
                moduleMapPath = clangModule.moduleMapPath
            } else {
                // Generate and drop the modulemap inside Xcodeproj folder.
                let path = xcodeprojPath.appending(components: "GeneratedModuleMap", clangModule.c99name)
                var moduleMapGenerator = ModuleMapGenerator(for: clangModule, fileSystem: fileSystem)
                try moduleMapGenerator.generateModuleMap(inDir: path)
                moduleMapPath = path.appending(component: moduleMapFilename)
            }
            includeGroup.addFileReference(path: moduleMapPath.asString, name: moduleMapPath.basename)
            targetSettings.common.MODULEMAP_FILE = moduleMapPath.relative(to: xcodeprojPath.parentDirectory).asString
        }
    }
    
    // Go through all the module/target pairs again, and add target dependencies
    // for any module dependencies.  As we go, we also add link phases and set
    // up the targets to link against the products of the dependencies.
    for (module, target) in modulesToTargets {
        // Add link build phase (which Xcode calls "Frameworks & Libraries").
        // We need to do this whether or not there are dependencies on other
        // modules.
        let linkPhase = target.addFrameworksBuildPhase()
        
        // For each module on which this one depends, add a target dependency
        // and also link against the target's product.
        for dependency in module.recursiveDependencies {
            // We should never find ourself in the list of dependencies.
            assert(dependency != module)
            
            // Find the target that corresponds to the other module.
            guard let otherTarget = modulesToTargets[dependency] else {
                // FIXME: We're depending on a module for which we didn't create
                // a target.  This is unexpected, and we should report this as
                // an error.
                // FIXME: Or is it?  What about system modules, can we depend
                // on those?  If so, we would just link and not depend, right?
                continue
            }
            
            // Add a dependency on the other target.
            target.addDependency(on: otherTarget)
            let _ = linkPhase.addBuildFile(fileRef: otherTarget.productReference!)
        }
    }

    return project
}

extension Module {

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
