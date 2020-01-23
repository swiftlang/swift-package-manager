/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

import PackageModel
import PackageGraph

/// PIF object builder for a package.
public final class PackagePIFBuilder {
    /// The package graph we're operating on.
    let graph: PackageGraph
    
    public init(_ graph: PackageGraph){
        self.graph = graph
    }

    /// Generates the PIF representation.
    public func generatePIF() throws -> String {
        let rootPackage = graph.rootPackages[0]

        let workspace = PIF.Workspace(
            guid: "Workspace:\(rootPackage.path.pathString)",
            path: rootPackage.path.pathString,
            name: rootPackage.name
        )

        for package in graph.packages {
            try workspace.projects.append(createPIFProject(package))
        }

        let pifData = try workspace.generatePIF()
        return String(data: pifData, encoding: .utf8)!
    }

    func createPIFProject(_ package: ResolvedPackage) throws -> PIF.Project {
        let pifProject = PIF.Project(
            id: "PACKAGE:\(package.manifest.url)",
            path: package.path.pathString,
            projectDir: package.path.pathString,
            name: package.name
        )

        // Configure the project-wide build settings.  First we set those that are in common between the "Debug" and "Release" configurations, and then we set those that are different.
        var settings = PIF.BuildSettings()
        settings.PRODUCT_NAME = "$(TARGET_NAME)"
        settings.SUPPORTED_PLATFORMS = ["$(AVAILABLE_PLATFORMS)"]
        settings.SDKROOT = "auto"
        settings.SDK_VARIANT = "auto"
        settings.SKIP_INSTALL = "YES"
        settings.DYLIB_INSTALL_NAME_BASE = "@rpath"
        settings.USE_HEADERMAP = "NO"
        settings.OTHER_SWIFT_FLAGS = ["$(inherited)", "-DXcode"]
        settings.OTHER_CFLAGS = ["$(inherited)", "-DXcode"]
        settings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = ["$(inherited)", "SWIFT_PACKAGE"]
        settings.GCC_PREPROCESSOR_DEFINITIONS = ["$(inherited)", "SWIFT_PACKAGE"]
        settings.CLANG_ENABLE_OBJC_ARC = "YES"
        settings.KEEP_PRIVATE_EXTERNS = "NO"
        // We currently deliberately do not support Swift ObjC interface headers.
        settings.SWIFT_INSTALL_OBJC_HEADER = "NO"
        settings.SWIFT_OBJC_INTERFACE_HEADER_NAME = ""
        settings.OTHER_LDRFLAGS = []

        // XCTest search paths should only be specified for certain platforms (watchOS doesn't have XCTest).
        let xctestSearchPath = ["$(PLATFORM_DIR)/Developer/Library/Frameworks"]
        settings.platformSpecificSettings[.macOS]![.FRAMEWORK_SEARCH_PATHS]!.append(contentsOf: xctestSearchPath)
        settings.platformSpecificSettings[.iOS]![.FRAMEWORK_SEARCH_PATHS]!.append(contentsOf: xctestSearchPath)
        settings.platformSpecificSettings[.tvOS]![.FRAMEWORK_SEARCH_PATHS]!.append(contentsOf: xctestSearchPath)

        // This will add the XCTest related search paths automatically
        // (including the Swift overlays).
        settings.ENABLE_TESTING_SEARCH_PATHS = "YES"

        // Disable signing for all the things since there is no way to configure
        // signing information in packages right now.
        settings.ENTITLEMENTS_REQUIRED = "NO"
        settings.CODE_SIGNING_REQUIRED = "NO"
        settings.CODE_SIGN_IDENTITY = ""

        // Add the build settings that are specific to debug builds, and set those as the "Debug" configuration.
        var debugSettings = settings
        debugSettings.COPY_PHASE_STRIP = "NO"
        debugSettings.DEBUG_INFORMATION_FORMAT = "dwarf"
        debugSettings.ENABLE_NS_ASSERTIONS = "YES"
        debugSettings.GCC_OPTIMIZATION_LEVEL = "0"
        debugSettings.ONLY_ACTIVE_ARCH = "YES"
        debugSettings.SWIFT_OPTIMIZATION_LEVEL = "-Onone"
        debugSettings.ENABLE_TESTABILITY = "YES"
        debugSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = (settings.SWIFT_ACTIVE_COMPILATION_CONDITIONS ?? []) + ["DEBUG"]
        debugSettings.GCC_PREPROCESSOR_DEFINITIONS = (settings.GCC_PREPROCESSOR_DEFINITIONS ?? ["$(inherited)"]) + ["DEBUG=1"]
        pifProject.addBuildConfig(name: "Debug", settings: debugSettings)

        // Add the build settings that are specific to release builds, and set those as the "Release" configuration.
        var releaseSettings = settings
        releaseSettings.COPY_PHASE_STRIP = "YES"
        releaseSettings.DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"
        releaseSettings.GCC_OPTIMIZATION_LEVEL = "s"
        releaseSettings.SWIFT_OPTIMIZATION_LEVEL = "-Owholemodule"
        pifProject.addBuildConfig(name: "Release", settings: releaseSettings)

        for product in package.products {
            guard product.type == .executable else {
                fatalError()
            }

            let pifTarget = pifProject.addTarget(
                id: pifTargetIdForProductName(product.name),
                productType: .executable,
                name: product.name,
                productName: product.name
            )

            // Configure the target-wide build settings.
            var settings = PIF.BuildSettings()
            settings.TARGET_NAME = product.name
            settings.PACKAGE_RESOURCE_TARGET_KIND = "regular"
            settings.PRODUCT_NAME = product.name
            settings.PRODUCT_MODULE_NAME = product.executableModule.c99name
            settings.PRODUCT_BUNDLE_IDENTIFIER = product.name
            settings.EXECUTABLE_NAME = product.name
            settings.CLANG_ENABLE_MODULES = "YES"
            settings.DEFINES_MODULE = "YES"
            settings.SWIFT_FORCE_STATIC_LINK_STDLIB = "NO"
            settings.SWIFT_FORCE_DYNAMIC_LINK_STDLIB = "YES"

            // FIXME: Don't hardcode.
            settings.SWIFT_VERSION = "5.0"

            let target = product.executableModule
            let mainTargetSourceFileGroup = pifProject.mainGroup.addGroup(path: target.sources.root.pathString, pathBase: .absolute)

            for source in target.sources.relativePaths {
                pifTarget.addSourceFile(ref: mainTargetSourceFileGroup.addFileReference(
                    path: source.pathString, pathBase: .groupDir))
            }

            let debugSettings = settings
            let releaseSettings = settings
            pifTarget.addBuildConfig(name: "Debug", settings: debugSettings)
            pifTarget.addBuildConfig(name: "Release", settings: releaseSettings)
        }

        return pifProject
    }

    // Helper function to consistently generate a PIF target identifier string for a product in a package.  This format helps make sure that there is no collision with any other PIF targets, and in particular that a PIF target and a PIF product can have the same name (as they often do).
    func pifTargetIdForProductName(_ name: String) -> String {
        return "PACKAGE-PRODUCT:\(name)"
    }

    // Helper function to consistently generate a PIF target identifier string for a target in a package.  This format helps make sure that there is no collision with any other PIF targets, and in particular that a PIF target and a PIF product can have the same name (as they often do).
    func pifTargetIdForTargetName(_ name: String) -> String {
        return "PACKAGE-TARGET:\(name)"
    }
}
