/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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
    let project = try xcodeProject(
        xcodeprojPath: xcodeprojPath,
        graph: graph,
        extraDirs: extraDirs,
        options: options,
        fileSystem: fileSystem)
    // Serialize the project model we created to a plist, and return
    // its string description.
    return "// !$*UTF8*$!\n" + project.generatePlist().description
}

/// A set of c99 target names that are invalid for Xcode Framework targets.
/// They will conflict with the required Framework directory structure,
/// and cause a linker error (SR-3398).
// FIXME: Handle case insensitive filesystems.
fileprivate let invalidXcodeModuleNames = Set(["Modules", "Headers", "Versions"])

func xcodeProject(
    xcodeprojPath: AbsolutePath,
    graph: PackageGraph,
    extraDirs: [AbsolutePath],
    options: XcodeprojOptions,
    fileSystem: FileSystem,
    warningStream: OutputByteStream = stdoutStream
    ) throws -> Xcode.Project {

    // Create the project.
    let project = Xcode.Project()

    // Generates a dummy target to provide autocompletion for the manifest file.
    func createPackageDescriptionTarget(for package: ResolvedPackage, manifestFileRef: Xcode.FileReference) {
        let pdTarget = project.addTarget(
            objectID: "\(package.name)::SwiftPMPackageDescription",
            productType: .framework, name: "\(package.name)PackageDescription")
        let compilePhase = pdTarget.addSourcesBuildPhase()
        compilePhase.addBuildFile(fileRef: manifestFileRef)
        pdTarget.buildSettings.common.OTHER_SWIFT_FLAGS += package.manifest.interpreterFlags
        pdTarget.buildSettings.common.SWIFT_VERSION = "\(package.manifest.manifestVersion.rawValue).0"
        pdTarget.buildSettings.common.LD = "/usr/bin/true"
    }

    // Determine the source root directory (which is NOT necessarily related in
    // any way to `xcodeprojPath`, i.e. we cannot assume that the Xcode project
    // will be generated into to the source root directory).
    let sourceRootDir = graph.rootPackages[0].path

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
    projectSettings.common.SUPPORTED_PLATFORMS = [
        "macosx",
        "iphoneos",
        "iphonesimulator",
        "appletvos",
        "appletvsimulator",
        "watchos",
        "watchsimulator",
    ]

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

    // Defined for regular `swift build` instantiations, so also should be defined here.
    projectSettings.common.SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SWIFT_PACKAGE"

    // Opt out of headermaps.  The semantics of the build should be explicitly
    // defined by the project structure, so that we don't get any additional
    // magic behavior that isn't present in `swift build`.
    projectSettings.common.USE_HEADERMAP = "NO"

    // Enable `Automatic Reference Counting` for Objective-C sources
    projectSettings.common.CLANG_ENABLE_OBJC_ARC = "YES"

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
    projectSettings.release.SWIFT_OPTIMIZATION_LEVEL = "-Owholemodule"

    // Add a file reference for the package manifest itself.
    // FIXME: We should parameterize this so that a package can return the path
    // of its manifest file.
    let manifestFileRef = project.mainGroup.addFileReference(path: "Package.swift", fileType: "sourcecode.swift")
    createPackageDescriptionTarget(for: graph.rootPackages[0], manifestFileRef: manifestFileRef)

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
        xcconfigOverridesFileRef = xcconfigsGroup.addFileReference(
            path: xcconfigPath.relative(to: sourceRootDir).asString,
            name: xcconfigPath.basename)

        // We don't assign the file reference as the xcconfig file reference of
        // the project's build settings, because if we do, the xcconfig cannot
        // override any of the default build settings at the project level.  So
        // we instead assign it to each target.

        // We may instead want to emit all build settings to separate .xcconfig
        // files that use `#include` to include the overriding .xcconfig file.
    } else {
        // Otherwise, we don't create an .xcconfig file reference.
        xcconfigOverridesFileRef = nil
    }

    // Determine the list of external package dependencies, if any.
    let externalPackages = graph.packages.filter({ !graph.rootPackages.contains($0) })

    // Build a backmap of targets and products to packages.
    var packagesByTarget = [ResolvedTarget: ResolvedPackage]()
    for package in graph.packages {
        for target in package.targets {
            packagesByTarget[target] = package
        }
    }
    var packagesByProduct = [ResolvedProduct: ResolvedPackage]()
    for package in graph.packages {
        for product in package.products {
            packagesByProduct[product] = package
        }
    }
    
    // To avoid creating multiple groups for the same path, we keep a mapping
    // of the paths we've seen and the corresponding groups we've created.
    var srcPathsToGroups: [AbsolutePath: Xcode.Group] = [:]

    // Private helper function to make a group (or return an existing one) for
    // a particular path, including any intermediate groups that may be needed.
    // A name can be specified, if different from the last path component (any
    // custom name does not apply to any intermediate groups).
    func makeGroup(for path: AbsolutePath, named name: String? = nil) -> Xcode.Group {
        // Check if we already have a group.
        if let group = srcPathsToGroups[path] {
            // We do, so we just return it without creating anything.
            return group
        }

        // No existing group, so start by making sure we have the parent.  Note
        // that we don't pass along any custom name for any parent groups.
        let parentGroup = makeGroup(for: path.parentDirectory)

        // Now we have a parent, so we can create a group, optionally using the
        // custom name we were given.
        let group = parentGroup.addGroup(path: path.basename, pathBase: .groupDir, name: name ?? path.basename)

        // Add the new group to the mapping, so future lookups will find it.
        srcPathsToGroups[path] = group
        return group
    }

    // Add a mapping from the project dir to the main group, as a backstop for
    // any paths that get that far (which does not happen in standard package
    // layout).
    srcPathsToGroups[sourceRootDir] = project.mainGroup

    // Private helper function that creates a source group for one or more
    // targets (which could be regular targets, tests, etc).  If there is a
    // single target whose source directory's basename is not equal to the
    // target name (i.e. the "flat" form of a single-target package), then
    // the top-level group will itself represent that target; otherwise, it
    // will have one subgroup for each target.
    //
    // The provided name is always used for the top-level group, whether or
    // not it represents a single target or is the parent of a collection of
    // targets.
    //
    // Regardless of the layout case, this function adds a mapping from the
    // source directory of each target to the corresponding group, so that
    // source files added later will be able to find the right group.
    @discardableResult
    func createSourceGroup(named groupName: String, for targets: [ResolvedTarget], in parentGroup: Xcode.Group) -> Xcode.Group? {
        // Look for the special case of a single target in a flat layout.
        let needsSourcesGroup: Bool
        if let target = targets.only {
            // FIXME: This is somewhat flaky; packages should have a notion of
            // what kind of layout they have.  But at least this is just a
            // heuristic and won't affect the functioning of the Xcode project.
            needsSourcesGroup = (target.sources.root.basename == target.name)
        } else {
            needsSourcesGroup = true
        }

        // If we need a sources group, create one.
        let sourcesGroup = needsSourcesGroup ?
            parentGroup.addGroup(path: "", pathBase: .projectDir, name: groupName) : nil

        // Create a group for each target.
        for target in targets {
            // The sources could be anywhere, so we use a project-relative path.
            let path = target.sources.root.relative(to: sourceRootDir).asString
            let name = (sourcesGroup == nil ? groupName : target.name)
            let group = (sourcesGroup ?? parentGroup)
                .addGroup(path: (path == "." ? "" : path), pathBase: .projectDir, name: name)

            // Associate the group with the target's root path.
            srcPathsToGroups[target.sources.root] = group
        }

        return sourcesGroup ?? srcPathsToGroups[targets[0].sources.root]
    }

    let (rootModules, testModules) = graph.rootPackages[0].targets.split{ $0.type != .test }

    // Create a `Sources` group for the source targets in the root package.
    createSourceGroup(named: "Sources", for: rootModules, in: project.mainGroup)

    // Create a `Tests` group for the source targets in the root package.
    createSourceGroup(named: "Tests", for: testModules, in: project.mainGroup)

    // Add "blue folders" for any other directories at the top level (note that
    // they are not guaranteed to be direct children of the root directory).
    for extraDir in extraDirs {
        project.mainGroup.addFileReference(path: extraDir.relative(to: sourceRootDir).asString, pathBase: .projectDir)
    }

    // Determine the set of targets to generate in the project by excluding
    // any system targets.
    let targets = graph.targets.filter({ $0.type != .systemModule })

    // If we have any external packages, we also add a `Dependencies` group at
    // the top level, along with a sources subgroup for each package.
    if !externalPackages.isEmpty {
        // Create the top-level `Dependencies` group.  We cannot count on each
        // external package's path, so we don't assign a particular path to the
        // `Dependencies` group; each package provides its own project-relative
        // path.
        let dependenciesGroup = project.mainGroup.addGroup(path: "", pathBase: .groupDir, name: "Dependencies")

        // Create set of the targets.
        let targetSet = Set(targets)

        // Add a subgroup for each external package.
        for package in externalPackages {
            // Skip if there are no targets in this package that needs to be built.
            if targetSet.intersection(package.targets).isEmpty {
                continue
            }
            // Construct a group name from the package name and optional version.
            var groupName = package.name
            if let version = package.manifest.version {
                groupName += " " + version.description
            }
            // Create the source group for all the targets in the package.
            // FIXME: Eliminate filtering test from here.
            let group = createSourceGroup(named: groupName, for: package.targets.filter({ $0.type != .test }), in: dependenciesGroup)
            if let group = group {
                let manifestPath = package.path.appending(component: "Package.swift")
                let manifestFileRef = group.addFileReference(path: manifestPath.asString, name: "Package.swift", fileType: "sourcecode.swift")
                createPackageDescriptionTarget(for: package, manifestFileRef: manifestFileRef)
            }
        }
    }

    // Add a `Products` group, to which we'll add references to the outputs of
    // the various targets; these references will be added to the link phases.
    let productsGroup = project.mainGroup.addGroup(path: "", pathBase: .buildDir, name: "Products")

    // Set the newly created `Products` group as the official products group of
    // the project.
    project.productGroup = productsGroup

    // We'll need a mapping of targets to the corresponding targets.
    var modulesToTargets: [ResolvedTarget: Xcode.Target] = [:]

    // Mapping of targets to the path of their modulemap path, if they one.
    // It also records if the modulemap is generated by SwiftPM.
    var modulesToModuleMap: [ResolvedTarget: (path: AbsolutePath, isGenerated: Bool)] = [:]

    // Go through all the targets, creating targets and adding file references
    // to the group tree (the specific top-level group under which they are
    // added depends on whether or not the target is a test target).
    for target in targets {
        // Determine the appropriate product type based on the kind of target.
        // FIXME: We should factor this out.
        let productType: Xcode.Target.ProductType
        switch target.type {
        case .executable:
            productType = .executable
        case .library:
            productType = .framework
        case .test:
            productType = .unitTest
        case .systemModule:
            fatalError()
        }

        // Warn if the target name is invalid.
        if target.type == .library && invalidXcodeModuleNames.contains(target.c99name) {
            warningStream <<< ("warning: Target '\(target.name)' conflicts with required framework filenames, rename " +
                "this target to avoid conflicts.\n")
            warningStream.flush()
        }

        // Create a Xcode target for the target.
        let package = packagesByTarget[target]!
        let xcodeTarget = project.addTarget(
            objectID: "\(package.name)::\(target.name)",
            productType: productType, name: target.name)

        // Set the product name to the C99-mangled form of the target name.
        xcodeTarget.productName = target.c99name

        // Configure the target settings based on the target.  We set only the
        // minimum settings required, because anything we set on the target is
        // not overridable by the user-supplied .xcconfig file.
        let targetSettings = xcodeTarget.buildSettings

        // Set the target's base .xcconfig file to the user-supplied override
        // .xcconfig, if we have one.  This lets it override project settings.
        targetSettings.xcconfigFileRef = xcconfigOverridesFileRef

        targetSettings.common.TARGET_NAME = target.name

        let infoPlistFilePath = xcodeprojPath.appending(component: target.infoPlistFileName)
        targetSettings.common.INFOPLIST_FILE = infoPlistFilePath.relative(to: sourceRootDir).asString

        if target.type == .test {
            targetSettings.common.EMBEDDED_CONTENT_CONTAINS_SWIFT = "YES"
            targetSettings.common.LD_RUNPATH_SEARCH_PATHS = ["@loader_path/../Frameworks", "@loader_path/Frameworks"]
        } else {
            // We currently force a search path to the toolchain, since we can't
            // establish an expected location for the Swift standard libraries.
            //
            // Note that this means that the built binaries are not suitable for
            // distribution, among other things.
            targetSettings.common.LD_RUNPATH_SEARCH_PATHS = ["$(TOOLCHAIN_DIR)/usr/lib/swift/macosx"]
            if target.type == .library {
                targetSettings.common.ENABLE_TESTABILITY = "YES"
                targetSettings.common.PRODUCT_NAME = "$(TARGET_NAME:c99extidentifier)"
                targetSettings.common.PRODUCT_MODULE_NAME = "$(TARGET_NAME:c99extidentifier)"
                targetSettings.common.PRODUCT_BUNDLE_IDENTIFIER = target.c99name.mangledToBundleIdentifier()
                targetSettings.common.SKIP_INSTALL = "YES"
            } else {
                targetSettings.common.SWIFT_FORCE_STATIC_LINK_STDLIB = "NO"
                targetSettings.common.SWIFT_FORCE_DYNAMIC_LINK_STDLIB = "YES"

                targetSettings.common.LD_RUNPATH_SEARCH_PATHS += ["@executable_path"]
            }
        }

        targetSettings.common.OTHER_LDFLAGS = ["$(inherited)"]
        targetSettings.common.OTHER_SWIFT_FLAGS = ["$(inherited)"]

        // Set the correct SWIFT_VERSION for the Swift targets.
        if case let swiftTarget as SwiftTarget = target.underlyingTarget {
            targetSettings.common.SWIFT_VERSION = "\(swiftTarget.swiftVersion).0"
        }

        // Add header search paths for any C target on which we depend.
        var hdrInclPaths = ["$(inherited)"]
        for depModule in [target] + target.recursiveDependencies {
            // FIXME: Possibly factor this out into a separate protocol; the
            // idea would be that we would ask the target how it contributes
            // to the overall build environment for client targets, which can
            // affect search paths and other flags.  This should be done in a
            // way that allows SwiftPM to detect incompatibilities.

            // FIXME: We don't need SRCROOT macro below but there is an issue with sourcekit.
            // See: <rdar://problem/21912068> SourceKit cannot handle relative include paths (working directory)
            switch depModule.underlyingTarget {
              case let cTarget as CTarget:
                hdrInclPaths.append("$(SRCROOT)/" + cTarget.path.relative(to: sourceRootDir).asString)
                if let pkgArgs = pkgConfigArgs(for: cTarget) {
                    targetSettings.common.OTHER_LDFLAGS += pkgArgs.libs
                    targetSettings.common.OTHER_SWIFT_FLAGS += pkgArgs.cFlags
                }
            case let clangTarget as ClangTarget:
                hdrInclPaths.append("$(SRCROOT)/" + clangTarget.includeDir.relative(to: sourceRootDir).asString)
              default:
                continue
            }
        }
        targetSettings.common.HEADER_SEARCH_PATHS = hdrInclPaths

        // Add framework search path to build settings.
        targetSettings.common.FRAMEWORK_SEARCH_PATHS = ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"]

        // Add a file reference for the target's product.
        let productRef = productsGroup.addFileReference(path: target.productPath.asString, pathBase: .buildDir, objectID: "\(package.name)::\(target.name)::Product")

        // Set that file reference as the target's product reference.
        xcodeTarget.productReference = productRef

        // Add a compile build phase (which Xcode calls "Sources").
        let compilePhase = xcodeTarget.addSourcesBuildPhase()

        // We don't add dependencies yet — we do so in a separate pass, since
        // some dependencies might be on targets that we have not yet created.

        // We also don't add the link phase yet, since we'll do so at the same
        // time as we set up dependencies.

        // Record the target that we created for this target, for later passes.
        modulesToTargets[target] = xcodeTarget

        // Go through the target source files.  As we do, we create groups for
        // any path components other than the last one.  We also add build files
        // to the compile phase of the target we created.
        for sourceFile in target.sources.paths {
            // Find or make a group for the parent directory of the source file.
            // We know that there will always be one, because we created groups
            // for the source directories of all the targets.
            let group = makeGroup(for: sourceFile.parentDirectory)

            // Create a reference for the source file.  We don't set its file
            // type; rather, we let Xcode determine it based on the suffix.
            let srcFileRef = group.addFileReference(path: sourceFile.basename)

            // Also add the source file to the compile phase.
            compilePhase.addBuildFile(fileRef: srcFileRef)
        }

        // Add the `include` group for a libary C language target.
        if case let clangTarget as ClangTarget = target.underlyingTarget,
            clangTarget.type == .library,
            fileSystem.isDirectory(clangTarget.includeDir) {
            let includeDir = clangTarget.includeDir
            let includeGroup = makeGroup(for: includeDir)
            // FIXME: Support C++ headers.
            for header in try walk(includeDir, fileSystem: fileSystem) where header.extension == "h" {
                let group = makeGroup(for: header.parentDirectory)
                group.addFileReference(path: header.basename)
            }

            // Disable defines target for clang target because our clang targets are not proper framework targets.
            // Also see: <rdar://problem/29825757> 
            targetSettings.common.DEFINES_MODULE = "NO"
            // Generate a modulemap for clangTarget (if not provided by user) and
            // add to the build settings.
            let moduleMapPath: AbsolutePath

            // If the modulemap is generated (as opposed to user provided).
            let isGenerated: Bool
            // If user provided the modulemap no need to generate.
            if fileSystem.isFile(clangTarget.moduleMapPath) {
                moduleMapPath = clangTarget.moduleMapPath
                isGenerated = false
            } else {
                // Generate and drop the modulemap inside Xcodeproj folder.
                let path = xcodeprojPath.appending(components: "GeneratedModuleMap", clangTarget.c99name)
                var moduleMapGenerator = ModuleMapGenerator(for: clangTarget, fileSystem: fileSystem)
                try moduleMapGenerator.generateModuleMap(inDir: path)
                moduleMapPath = path.appending(component: moduleMapFilename)
                isGenerated = true
            }
            includeGroup.addFileReference(path: moduleMapPath.asString, name: moduleMapPath.basename)
            // Save this modulemap path mapped to target so we can later wire it up for its dependees.
            modulesToModuleMap[target] = (moduleMapPath, isGenerated)
        }
    }

    // Go through all the target/target pairs again, and add target dependencies
    // for any target dependencies.  As we go, we also add link phases and set
    // up the targets to link against the products of the dependencies.
    for (target, xcodeTarget) in modulesToTargets {
        // Add link build phase (which Xcode calls "Frameworks & Libraries").
        // We need to do this whether or not there are dependencies on other
        // targets.
        let linkPhase = xcodeTarget.addFrameworksBuildPhase()

        // For each target on which this one depends, add a target dependency
        // and also link against the target's product.
        for dependency in target.recursiveDependencies {
            // We should never find ourself in the list of dependencies.
            assert(dependency != target)

            // Find the target that corresponds to the other target.
            guard let otherTarget = modulesToTargets[dependency] else {
                // FIXME: We're depending on a target for which we didn't create
                // a target.  This is unexpected, and we should report this as
                // an error.
                // FIXME: Or is it?  What about system targets, can we depend
                // on those?  If so, we would just link and not depend, right?
                continue
            }

            // Add a dependency on the other target.
            xcodeTarget.addDependency(on: otherTarget)

            // If it's a library, we also add want to link against its product.
            if dependency.type == .library {
                _ = linkPhase.addBuildFile(fileRef: otherTarget.productReference!)
            }
            // For swift targets, if a clang dependency has a modulemap, add it via -fmodule-map-file.
            if let moduleMap = modulesToModuleMap[dependency], target.underlyingTarget is SwiftTarget {
                assert(dependency.underlyingTarget is ClangTarget)
                xcodeTarget.buildSettings.common.OTHER_SWIFT_FLAGS += [
                    "-Xcc",
                    "-fmodule-map-file=$(SRCROOT)/" + moduleMap.path.relative(to: sourceRootDir).asString,
                ]
                // Workaround for a interface generation bug. <rdar://problem/30071677>
                if moduleMap.isGenerated {
                    xcodeTarget.buildSettings.common.HEADER_SEARCH_PATHS += [
                        "$(SRCROOT)/" + moduleMap.path.parentDirectory.relative(to: sourceRootDir).asString
                    ]
                }
            }
        }
    }

    // Create an aggregate target for every product for which there isn't already
    // a target with the same name.
    let targetNames: Set<String> = Set(modulesToTargets.values.map({ $0.name }))
    for product in graph.products {
        // Go on to next product if we already have a target with the same name.
        if targetNames.contains(product.name) { continue }
        // Otherwise, create an aggreate target.
        let package = packagesByProduct[product]!
        let aggregateTarget = project.addTarget(
            objectID: "\(package.name)::\(product.name)::ProductTarget",
            productType: nil, name: product.name)
        // Add dependencies on the targets created for each of the dependencies.
        for target in product.targets {
            // Find the target that corresponds to the target.  There might not
            // be one, since we don't create targets for every kind of target
            // (such as system targets).
            // TODO: We will need to decide how this should best be handled; it
            // would make sense to at least emit a warning.
            guard let depTarget = modulesToTargets[target] else {
                continue
            }
            // Add a dependency on the dependency target.
            aggregateTarget.addDependency(on: depTarget)
        }
    }

    return project
}

extension ResolvedTarget {

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

private extension ResolvedTarget {
    func fileType(forSource source: RelativePath) -> String {
        switch underlyingTarget {
        case is SwiftTarget:
            // SwiftModules only has one type of source so just always return this.
            return SupportedLanguageExtension.swift.xcodeFileType

        case is ClangTarget:
            guard let suffix = source.suffix else {
                fatalError("Source \(source) doesn't have an extension in ClangModule \(name)")
            }
            // Suffix includes `.` so drop it.
            assert(suffix.hasPrefix("."))
            let fileExtension = String(suffix.dropFirst())
            guard let ext = SupportedLanguageExtension(rawValue: fileExtension) else {
                fatalError("Unknown source extension \(source) in ClangModule \(name)")
            }
            return ext.xcodeFileType

        default:
            fatalError("unexpected target type")
        }
    }
}
