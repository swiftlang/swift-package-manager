//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import TSCBasic

public final class MixedTargetBuildDescription {
    /// The target described by this target.
    let target: ResolvedTarget

    /// The list of all resource files in the target.
    var resources: [Resource] { self.target.underlyingTarget.resources }

    /// If this target is a test target.
    var isTestTarget: Bool { self.target.underlyingTarget.type == .test }

    /// The objects in this target. This includes both the Swift and Clang object files.
    var objects: [AbsolutePath] {
        get throws {
            try self.swiftTargetBuildDescription.objects +
                self.clangTargetBuildDescription.objects
        }
    }

    /// Path to the bundle generated for this module (if any).
    var bundlePath: AbsolutePath? { self.swiftTargetBuildDescription.bundlePath }

    /// Path to the resource Info.plist file, if generated.
    var resourceBundleInfoPlistPath: AbsolutePath? {
        self.swiftTargetBuildDescription.resourceBundleInfoPlistPath
    }

    /// The path to the VFS overlay file that overlays the public headers of
    /// the Clang part of the target over the target's build directory.
    let allProductHeadersOverlay: AbsolutePath

    /// The paths to the targets's public headers.
    let publicHeaderPaths: [AbsolutePath]

    /// The modulemap file for this target.
    let moduleMap: AbsolutePath

    /// Paths to the binary libraries the target depends on.
    var libraryBinaryPaths: Set<AbsolutePath> {
        self.swiftTargetBuildDescription.libraryBinaryPaths
            .union(self.clangTargetBuildDescription.libraryBinaryPaths)
    }

    /// The build description for the Clang sources.
    let clangTargetBuildDescription: ClangTargetBuildDescription

    /// The build description for the Swift sources.
    let swiftTargetBuildDescription: SwiftTargetBuildDescription

    init(
        package: ResolvedPackage,
        target: ResolvedTarget,
        toolsVersion: ToolsVersion,
        additionalFileRules: [FileRuleDescription] = [],
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [BuildToolPluginInvocationResult] = [],
        prebuildCommandResults: [PrebuildCommandResult] = [],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        guard let mixedTarget = target.underlyingTarget as? MixedTarget else {
            throw InternalError("underlying target type mismatch \(target)")
        }

        guard buildParameters.triple.isDarwin() else {
            throw StringError("Targets with mixed language sources are only " +
                "supported on Apple platforms.")
        }

        self.target = target

        let clangResolvedTarget = ResolvedTarget(
            target: mixedTarget.clangTarget,
            dependencies: target.dependencies,
            defaultLocalization: target.defaultLocalization,
            platforms: target.platforms
        )
        self.clangTargetBuildDescription = try ClangTargetBuildDescription(
            target: clangResolvedTarget,
            toolsVersion: toolsVersion,
            buildParameters: buildParameters,
            fileSystem: fileSystem,
            isWithinMixedTarget: true
        )

        let swiftResolvedTarget = ResolvedTarget(
            target: mixedTarget.swiftTarget,
            dependencies: target.dependencies,
            defaultLocalization: target.defaultLocalization,
            platforms: target.platforms
        )
        self.swiftTargetBuildDescription = try SwiftTargetBuildDescription(
            package: package,
            target: swiftResolvedTarget,
            toolsVersion: toolsVersion,
            additionalFileRules: additionalFileRules,
            buildParameters: buildParameters,
            buildToolPluginInvocationResults: buildToolPluginInvocationResults,
            prebuildCommandResults: prebuildCommandResults,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            isWithinMixedTarget: true
        )

        let interopHeaderPath = self.swiftTargetBuildDescription.objCompatibilityHeaderPath

        // A mixed target's build directory uses three subdirectories to
        // distinguish between build artifacts:
        // - Intermediates: Stores artifacts used during the target's build.
        // - Product: Stores artifacts used by clients of the target.
        // - InteropSupport: If needed, stores a generated umbrella header
        //   for use during the target's build and by clients of the target.
        let tempsPath = buildParameters.buildPath.appending(component: target.c99name + ".build")
        let intermediatesDirectory = tempsPath.appending(component: "Intermediates")
        let productDirectory = tempsPath.appending(component: "Product")
        let interopSupportDirectory: AbsolutePath?

        // Filenames for VFS overlay files.
        let allProductHeadersFilename = "all-product-headers.yaml"
        let unextendedModuleOverlayFilename = "unextended-module-overlay.yaml"

        // Used to generate both product and intermediate artifacts for the
        // target.
        let moduleMapGenerator = ModuleMapGenerator(
            targetName: mixedTarget.clangTarget.name,
            moduleName: mixedTarget.clangTarget.c99name,
            publicHeadersDir: mixedTarget.clangTarget.includeDir,
            fileSystem: fileSystem
        )

        // MARK: Conditionally generate an umbrella header for interoptability

        // When the Swift compiler creates the generated interop header
        // (`$(ModuleName)-Swift.h`) for Objective-C compatible Swift API
        // (via `-emit-objc-header`), any Objective-C symbol that cannot be
        // forward declared (e.g. superclass, protocol, etc.) will attempt to
        // be imported via a bridging or umbrella header. Since the compiler
        // evaluates the target as a framework (as opposed to an app), the
        // compiler assumes* an umbrella header exists in a subdirectory (named
        // after the module) within the public headers directory:
        //
        //      #import <$(ModuleName)/$(ModuleName).h>
        //
        // The compiler assumes that the above path can be resolved relative to
        // the public header directory. Instead of forcing package authors to
        // structure their packages around that constraint, the package manager
        // generates an umbrella header if needed and will pass it along as a
        // header search path when building the target.
        //
        // *: https://developer.apple.com/documentation/swift/importing-objective-c-into-swift
        let umbrellaHeaderPathComponents = [mixedTarget.c99name, "\(mixedTarget.c99name).h"]
        let potentialUmbrellaHeadersPath = mixedTarget.clangTarget.includeDir
            .appending(components: umbrellaHeaderPathComponents)
        // Check if an umbrella header at
        // `PUBLIC_HDRS_DIR/$(ModuleName)/$(ModuleName).h` already exists.
        if !fileSystem.isFile(potentialUmbrellaHeadersPath) {
            interopSupportDirectory = tempsPath.appending(component: "InteropSupport")
            let generatedUmbrellaHeaderPath = interopSupportDirectory!
                .appending(components: umbrellaHeaderPathComponents)
            // Populate a stream that will become the generated umbrella header.
            let stream = BufferedOutputByteStream()
            mixedTarget.clangTarget.headers
                // One of the requirements for a Swift API to be Objective-C
                // compatible and therefore included in the generated interop
                // header is that it has `public` or `open` visbility. This
                // means that such Swift API can only reference (e.g. subclass)
                // Objective-C types defined in the target's public headers.
                // Because of this, the generated umbrella header will only
                // include public headers so all other can be filtered out.
                .filter { $0.isDescendant(of: mixedTarget.clangTarget.includeDir) }
                // Filter out non-Objective-C/C headers.
                // TODO(ncooke3): C++ headers can be ".h". How else can we rule them out?
                .filter { $0.basename.hasSuffix(".h") }
                // Add each remaining header to the generated umbrella header.
                .forEach {
                    // Import the header, followed by a newline.
                    stream <<< "#import \"\($0)\"\n"
                }

            try fileSystem.writeFileContentsIfNeeded(
                generatedUmbrellaHeaderPath,
                bytes: stream.bytes
            )
        } else {
            // An umbrella header in the desired format already exists so the
            // interop support directory is not needed.
            interopSupportDirectory = nil
        }

        // Clients will later depend on the public header directory, and, if an
        // umbrella header was created, the header's root directory.
        self.publicHeaderPaths = interopSupportDirectory != nil ?
            [mixedTarget.clangTarget.includeDir, interopSupportDirectory!] :
            [mixedTarget.clangTarget.includeDir]

        // MARK: Generate products to be used by client of the target.

        // Path to the module map used by clients to access the mixed target's
        // public API.
        let productModuleMapPath = productDirectory.appending(component: moduleMapFilename)

        switch mixedTarget.clangTarget.moduleMapType {
        // When the mixed target has a custom module map, clients of the target
        // will be passed a module map *and* VFS overlay at buildtime to access
        // the mixed target's public API. The following is therefore needed:
        // - Create a copy of the custom module map, adding a submodule to
        //   expose the target's generated interop header. This allows clients
        //   of the target to consume the mixed target's public Objective-C
        //   compatible Swift API in a Clang context.
        // - Create a VFS overlay to swap in the modified module map for the
        //   original custom module map. This is done so relative paths in the
        //   modified module map can be resolved as they would have been in the
        //   original module map.
        case .custom(let customModuleMapPath):
            let customModuleMapContents: String =
                try fileSystem.readFileContents(customModuleMapPath)

            // Check that custom module map does not contain a Swift submodule.
            if customModuleMapContents.contains("\(target.c99name).Swift") {
                throw StringError(
                    "The target's module map may not contain a Swift " +
                        "submodule for the module \(target.c99name)."
                )
            }

            // Extend the contents and write it to disk, if needed.
            let stream = BufferedOutputByteStream()
            stream <<< customModuleMapContents
            stream <<< """
            module \(target.c99name).Swift {
                header "\(interopHeaderPath)"
                requires objc
            }
            """
            try fileSystem.writeFileContentsIfNeeded(
                productModuleMapPath,
                bytes: stream.bytes
            )

            // Set the original custom module map path as the module map path
            // for the target. The below VFS overlay will redirect to the
            // contents of the modified module map.
            self.moduleMap = customModuleMapPath
            self.allProductHeadersOverlay = productDirectory.appending(component: allProductHeadersFilename)

            try VFSOverlay(roots: [
                VFSOverlay.Directory(
                    name: customModuleMapPath.parentDirectory.pathString,
                    contents: [
                        // Redirect the custom `module.modulemap` to the
                        // modified module map in the product directory.
                        VFSOverlay.File(
                            name: moduleMapFilename,
                            externalContents: productModuleMapPath.pathString
                        ),
                        // Add a generated Swift header that redirects to the
                        // generated header in the build directory's root.
                        VFSOverlay.File(
                            name: interopHeaderPath.basename,
                            externalContents: interopHeaderPath.pathString
                        ),
                    ]
                ),
            ]).write(to: self.allProductHeadersOverlay, fileSystem: fileSystem)

        // When the mixed target does not have a custom module map, one will be
        // generated as a product for use by clients.
        // - Note: When `.none`, the mixed target has no public headers. Even
        //   then, a module map is created to expose the generated interop
        //   header so clients can access the public Objective-C compatible
        //   Swift API in a Clang context.
        case .umbrellaHeader, .umbrellaDirectory, .none:
            let generatedModuleMapType = mixedTarget.clangTarget.moduleMapType.generatedModuleMapType
            try moduleMapGenerator.generateModuleMap(
                type: generatedModuleMapType,
                at: productModuleMapPath,
                interopHeaderPath: interopHeaderPath
            )

            // Set the generated module map as the module map for the target.
            self.moduleMap = productModuleMapPath
            self.allProductHeadersOverlay = productDirectory.appending(component: allProductHeadersFilename)

            try VFSOverlay(roots: [
                VFSOverlay.Directory(
                    name: mixedTarget.clangTarget.includeDir.pathString,
                    contents: [
                        // Add a generated Swift header that redirects to the
                        // generated header in the build directory's root.
                        VFSOverlay.File(
                            name: interopHeaderPath.basename,
                            externalContents: interopHeaderPath.pathString
                        ),
                    ]
                ),
            ]).write(to: self.allProductHeadersOverlay, fileSystem: fileSystem)
        }

        // MARK: Generate intermediate artifacts used to build the target.

        // Building a mixed target uses intermediate module maps to expose
        // private headers to the Swift part of the module.

        // 1. Generate an intermediate module map that exposes all headers,
        // including the submodule with the generated Swift header.
        let intermediateModuleMapPath = intermediatesDirectory.appending(component: moduleMapFilename)
        try moduleMapGenerator.generateModuleMap(
            type: .umbrellaDirectory(mixedTarget.clangTarget.path),
            at: intermediateModuleMapPath,
            interopHeaderPath: interopHeaderPath
        )

        // 2. Generate an intermediate module map that exposes all headers.
        // When building the Swift part of the mixed target, a module map will
        // be needed to access types from the Objective-C part of the target.
        // However, this module map should not expose the generated Swift
        // header since it will not exist yet.
        let unextendedModuleMapPath = intermediatesDirectory.appending(component: unextendedModuleMapFilename)
        // Generating module maps that include non-Objective-C headers is not
        // supported.
        // FIXME(ncooke3): Link to evolution post.
        // TODO(ncooke3): C++ headers can be ".h". How else can we rule them out?
        let nonObjcHeaders: [AbsolutePath] = mixedTarget.clangTarget.headers
            .filter { $0.extension != "h" }
        try moduleMapGenerator.generateModuleMap(
            type: .umbrellaDirectory(mixedTarget.clangTarget.path),
            at: unextendedModuleMapPath,
            excludeHeaders: nonObjcHeaders
        )

        // 3. Use VFS overlays to purposefully expose specific resources (e.g.
        // module map) during the build. The directory to add a VFS overlay in
        // depends on the presence of a custom module map.
        let rootOverlayResourceDirectory: AbsolutePath
        if case .custom(let customModuleMapPath) = mixedTarget.clangTarget.moduleMapType {
            // To avoid the custom module map causing a module redeclaration
            // error, a VFS overlay is used when building the target to
            // redirect the custom module map to the modified module map in the
            // build directory. This redirecting overlay is placed in the
            // custom module map's parent directory, as to replace it.
            rootOverlayResourceDirectory = customModuleMapPath.parentDirectory
        } else {
            // Since no custom module map exists, the build directory can
            // be used as the root of the VFS overlay. In this case, the
            // VFS overlay's sole purpose is to expose the generated Swift
            // header.
            rootOverlayResourceDirectory = intermediatesDirectory
        }

        let allProductHeadersPath = intermediatesDirectory.appending(component: allProductHeadersFilename)
        try VFSOverlay(roots: [
            VFSOverlay.Directory(
                name: rootOverlayResourceDirectory.pathString,
                contents: [
                    // Redirect the `module.modulemap` to the modified
                    // module map in the intermediates directory.
                    VFSOverlay.File(
                        name: moduleMapFilename,
                        externalContents: intermediateModuleMapPath.pathString
                    ),
                    // Add a generated Swift header that redirects to the
                    // generated header in the build directory's root.
                    VFSOverlay.File(
                        name: interopHeaderPath.basename,
                        externalContents: interopHeaderPath.pathString
                    ),
                ]
            ),
        ]).write(to: allProductHeadersPath, fileSystem: fileSystem)

        let unextendedModuleMapOverlayPath = intermediatesDirectory
            .appending(component: unextendedModuleOverlayFilename)
        try VFSOverlay(roots: [
            VFSOverlay.Directory(
                name: rootOverlayResourceDirectory.pathString,
                contents: [
                    // Redirect the `module.modulemap` to the *unextended*
                    // module map in the intermediates directory.
                    VFSOverlay.File(
                        name: moduleMapFilename,
                        externalContents: unextendedModuleMapPath.pathString
                    ),
                ]
            ),
        ]).write(to: unextendedModuleMapOverlayPath, fileSystem: fileSystem)

        // 4. Tie everything together by passing build flags.

        // Importing the underlying module will build the Objective-C
        // part of the module. In order to find the underlying module,
        // a `module.modulemap` needs to be discoverable via a header
        // search path.
        self.swiftTargetBuildDescription.additionalFlags += [
            "-import-underlying-module",
            "-I", rootOverlayResourceDirectory.pathString,
        ]

        self.swiftTargetBuildDescription.appendClangFlags(
            // Pass both VFS overlays to the underlying Clang compiler.
            "-ivfsoverlay", allProductHeadersPath.pathString,
            "-ivfsoverlay", unextendedModuleMapOverlayPath.pathString,
            // Adding the root of the target's source as a header search
            // path allows for importing headers using paths relative to
            // the root.
            "-I", mixedTarget.path.pathString,
            // TODO(ncooke3): When there are no public headers, what happens?
            // What is exposed outside of the module?
            // TODO(ncooke3): Add comment about below line.
            // TODO(ncooke3): Think hard about further edge cases.
            "-I", mixedTarget.clangTarget.includeDir.pathString
        )

        self.clangTargetBuildDescription.additionalFlags += [
            // Adding the root of the target's source as a header search
            // path allows for importing headers using paths relative to
            // the root.
            "-I", mixedTarget.path.pathString,
            // Include overlay file to add interop header to overlay directory.
            "-ivfsoverlay", allProductHeadersPath.pathString,
            // The above two args add the interop header in the overlayed
            // directory. Pass the overlay directory as a search path so the
            // generated header can be imported.
            "-I", intermediatesDirectory.pathString,
        ]

        // If a generated umbrella header was created, add its root directory
        // as a header search path. This will resolve its import within the
        // generated interop header.
        if let interopSupportDirectory = interopSupportDirectory {
            self.swiftTargetBuildDescription.appendClangFlags(
                "-I", interopSupportDirectory.pathString
            )
            self.clangTargetBuildDescription.additionalFlags += [
                "-I", interopSupportDirectory.pathString,
            ]
        }
    }
}
