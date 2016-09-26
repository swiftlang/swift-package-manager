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

public struct XcodeprojOptions {
    /// The build flags.
    public var flags = BuildFlags()
    
    /// If provided, a path to an xcconfig file to be included by the project.
    ///
    /// This allows the client to override settings defined in the project itself.
    public var xcconfigOverrides: AbsolutePath?

    /// Whether code coverage should be enabled in the generated scheme.
    public var enableCodeCoverage = false
    
    public init() {
        // Ideally we shouldn't need an empty initializer but if we don't have
        // one we cannot instantiate a `XcodeprojOptions` struct from outside
        // the `Xcodeproj` module.
    }
}

/// Generates an Xcode project and all needed support files.  The .xcodeproj
/// wrapper directory is created in the path specified by `outputDir`, basing
/// the file name on the project name `projectName`.  Returns the path of the
/// generated project.  All ancillary files will be generated inside of the
/// .xcodeproj wrapper directory.
public func generate(outputDir: AbsolutePath, projectName: String, graph: PackageGraph, options: XcodeprojOptions) throws -> AbsolutePath {
    
    // Note that the output directory might be completely separate from the
    // path of the root package (which is where the sources live).
    
    let srcroot = graph.rootPackage.path
    
    // Determine the path of the .xcodeproj wrapper directory.
    let xcodeprojName = "\(projectName).xcodeproj"
    let xcodeprojPath = outputDir.appending(RelativePath(xcodeprojName))
    
    // Determine the path of the scheme directory (it's inside the .xcodeproj).
    let schemesDir = xcodeprojPath.appending(components: "xcshareddata", "xcschemes")
    
    // Create the .xcodeproj wrapper directory.
    try makeDirectories(xcodeprojPath)
    try makeDirectories(schemesDir)
    
    // Find the paths of any extra directories that should be added as folder
    // references in the project.
    let extraDirs = try findDirectoryReferences(path: srcroot)
    
    /// Generate the contents of project.xcodeproj (inside the .xcodeproj).
    try open(xcodeprojPath.appending(component: "project.pbxproj")) { stream in
        // FIXME: This could be more efficient by directly writing to a stream
        // instead of first creating a string.
        let str = try pbxproj(xcodeprojPath: xcodeprojPath, graph: graph, extraDirs: extraDirs, options: options)
        stream(str)
    }

////// the scheme acts like an aggregate target for all our targets
   /// it has all tests associated so CMD+U works
    let schemeName = "\(projectName).xcscheme"
    try open(schemesDir.appending(RelativePath(schemeName))) { stream in
        xcscheme(container: xcodeprojPath.relative(to: srcroot).asString, graph: graph, enableCodeCoverage: options.enableCodeCoverage, printer: stream)
    }

////// we generate this file to ensure our main scheme is listed
   /// before any inferred schemes Xcode may autocreate
    try open(schemesDir.appending(component: "xcschememanagement.plist")) { print in
        print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        print("<plist version=\"1.0\">")
        print("<dict>")
        print("  <key>SchemeUserState</key>")
        print("  <dict>")
        print("    <key>\(schemeName)</key>")
        print("    <dict></dict>")
        print("  </dict>")
        print("  <key>SuppressBuildableAutocreation</key>")
        print("  <dict></dict>")
        print("</dict>")
        print("</plist>")
    }

    for module in graph.modules where module.isLibrary {
        ///// For framework targets, generate module.c99Name_Info.plist files in the 
        ///// directory that Xcode project is generated
        let name = module.infoPlistFileName
        try open(xcodeprojPath.appending(RelativePath(name))) { print in
            print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
            print("<plist version=\"1.0\">")
            print("<dict>")
            print("  <key>CFBundleDevelopmentRegion</key>")
            print("  <string>en</string>")
            print("  <key>CFBundleExecutable</key>")
            print("  <string>$(EXECUTABLE_NAME)</string>")
            print("  <key>CFBundleIdentifier</key>")
            print("  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>")
            print("  <key>CFBundleInfoDictionaryVersion</key>")
            print("  <string>6.0</string>")
            print("  <key>CFBundleName</key>")
            print("  <string>$(PRODUCT_NAME)</string>")
            print("  <key>CFBundlePackageType</key>")
            if module.isTest {
                print("  <string>BNDL</string>")
            } else {
                print("  <string>FMWK</string>")
            }
            print("  <key>CFBundleShortVersionString</key>")
            print("  <string>1.0</string>")
            print("  <key>CFBundleSignature</key>")
            print("  <string>????</string>")
            print("  <key>CFBundleVersion</key>")
            print("  <string>$(CURRENT_PROJECT_VERSION)</string>")
            print("  <key>NSPrincipalClass</key>")
            print("  <string></string>")
            print("</dict>")
            print("</plist>")
        }
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
/// Excludes hidden directories, Xcode projects and reserved directories
func findDirectoryReferences(path: AbsolutePath) throws -> [AbsolutePath] {
    let rootDirectories = try walk(path, recursively: false)

    return rootDirectories.filter {
        if $0.suffix == ".xcodeproj" { return false }
        if $0.suffix == ".playground" { return false }
        if $0.basename.hasPrefix(".") { return false }
        if PackageBuilder.isReservedDirectory(pathComponent: $0.basename) { return false }
        return isDirectory($0)
    }
}
