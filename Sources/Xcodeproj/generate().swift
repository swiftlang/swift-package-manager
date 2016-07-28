/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Foundation
import POSIX
import PackageGraph
import PackageModel
import Utility

public struct XcodeprojOptions {
    /// The build flags.
    public var flags: BuildFlags
    
    /// If provided, a path to an xcconfig file to be included by the project.
    ///
    /// This allows the client to override settings defined in the project itself.
    public var xcconfigOverrides: AbsolutePath?

    /// Whether code coverage should be enabled in the generated scheme.
    public var enableCodeCoverage: Bool
    
    public init(flags: BuildFlags = BuildFlags(), xcconfigOverrides: AbsolutePath? = nil, enableCodeCoverage: Bool = false) {
        self.flags = flags
        self.xcconfigOverrides = xcconfigOverrides
        self.enableCodeCoverage = enableCodeCoverage
    }
}

/**
 Generates an xcodeproj at the specified path.
 - Returns: the path to the generated project
*/
public func generate(dstdir: AbsolutePath, projectName: String, graph: PackageGraph, options: XcodeprojOptions) throws -> AbsolutePath {
    let srcroot = graph.rootPackage.path

    // Filter out the CModule type, which we don't support.

    let xcodeprojName = "\(projectName).xcodeproj"
    let xcodeprojPath = dstdir.appending(RelativePath(xcodeprojName))
    let schemesDirectory = xcodeprojPath.appending(components: "xcshareddata", "xcschemes")
    try makeDirectories(xcodeprojPath)
    try makeDirectories(schemesDirectory)
    let schemeName = "\(projectName).xcscheme"
    let directoryReferences = try findDirectoryReferences(path: srcroot)

////// the pbxproj file describes the project and its targets
    try open(xcodeprojPath.appending(component: "project.pbxproj")) { stream in
        try pbxproj(srcroot: srcroot, projectRoot: dstdir, xcodeprojPath: xcodeprojPath, graph: graph, directoryReferences: directoryReferences, options: options, printer: stream)
    }

////// the scheme acts like an aggregate target for all our targets
   /// it has all tests associated so CMD+U works
    try open(schemesDirectory.appending(RelativePath(schemeName))) { stream in
        xcscheme(container: xcodeprojName, graph: graph, enableCodeCoverage: options.enableCodeCoverage, printer: stream)
    }

////// we generate this file to ensure our main scheme is listed
   /// before any inferred schemes Xcode may autocreate.
    let xcschememanagement = [
        "SchemeUserState": [
            schemeName: [:],
            "SuppressBuildableAutocreation": [:],
        ]
    ]
    NSDictionary(dictionary: xcschememanagement).write(toFile: schemesDirectory.appending(component: "xcschememanagement.plist").asString, atomically: true)
    
    for module in graph.modules where module.isLibrary {
        ///// For framework targets, generate module.c99Name_Info.plist files in the 
        ///// directory that Xcode project is generated
        let name = module.infoPlistFileName
        let path = xcodeprojPath.appending(RelativePath(name)).asString
        let packageType = module.isTest ? "BNDL" : "FMWK"
        
        let scheme = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundlePackageType": packageType,
            "CFBundleShortVersionString": "1.0",
            "CFBundleSignature": "????",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "NSPrincipalClass": ""
        ]
        NSDictionary(dictionary: scheme).write(toFile: path, atomically: true)
        NSDictionary(dictionary: scheme).write(toFile: "/Users/chris/test.plist", atomically: true)
    }

    return xcodeprojPath
}

/// Writes the contents to the file specified.
///
/// This method doesn't rewrite the file in case the new and old contents of
/// file are same.
func open(_ path: AbsolutePath, body: ((String) -> Void) throws -> Void) throws {
    let stream = BufferedOutputByteStream()
    try body { line in
        stream <<< line
        stream <<< "\n"
    }
    // If the file exists with the identical contents, we don't need to rewrite it.
    //
    // This avoids unnecessarily triggering Xcode reloads of the project file.
    if let contents = try? localFileSystem.readFileContents(path), contents == stream.bytes {
        return
    }

    // Write the real file.
    try localFileSystem.writeFileContents(path, bytes: stream.bytes)
}

/// Finds directories that will be added as blue folder
/// Excludes hidden directories and Xcode projects and directories that contains source code
func findDirectoryReferences(path: AbsolutePath) throws -> [AbsolutePath] {
    let rootDirectories = try walk(path, recursively: false)
    let rootDirectoriesToConsider = rootDirectories.filter {
        if $0.suffix == ".xcodeproj" { return false }
        if $0.suffix == ".playground" { return false }
        if $0.basename.hasPrefix(".") { return false }
        return isDirectory($0)
    }
    
    let filteredDirectories = try rootDirectoriesToConsider.filter {
        let directoriesWithSources = try walk($0).filter {
            guard let fileExt = $0.extension else { return false }
            return SupportedLanguageExtension.validExtensions.contains(fileExt)
        }
        return directoriesWithSources.isEmpty
    }

    return filteredDirectories;
}
