/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageGraph
import PackageModel
import PackageLoading
import SourceControl
import TSCUtility

public struct XcodeprojOptions {
    /// The build flags.
    public var flags: BuildFlags

    /// If provided, a path to an xcconfig file to be included by the project.
    ///
    /// This allows the client to override settings defined in the project itself.
    public var xcconfigOverrides: AbsolutePath?

    /// Whether code coverage should be enabled in the generated scheme.
    public var isCodeCoverageEnabled: Bool

    /// Whether to use legacy scheme generation logic.
    public var useLegacySchemeGenerator: Bool

    /// Run watchman to auto-generate the project file on changes.
    public var enableAutogeneration: Bool

    /// Whether to add extra files to the generated project.
    public var addExtraFiles: Bool

    /// Reference to manifest loader, if present.
    public var manifestLoader: ManifestLoader?

    public init(
        flags: BuildFlags = BuildFlags(),
        xcconfigOverrides: AbsolutePath? = nil,
        isCodeCoverageEnabled: Bool? = nil,
        useLegacySchemeGenerator: Bool? = nil,
        enableAutogeneration: Bool? = nil,
        addExtraFiles: Bool? = nil
    ) {
        self.flags = flags
        self.xcconfigOverrides = xcconfigOverrides
        self.isCodeCoverageEnabled = isCodeCoverageEnabled ?? false
        self.useLegacySchemeGenerator = useLegacySchemeGenerator ?? false
        self.enableAutogeneration = enableAutogeneration ?? false
        self.addExtraFiles = addExtraFiles ?? true
    }
}

// Determine the path of the .xcodeproj wrapper directory.
public func buildXcodeprojPath(outputDir: AbsolutePath, projectName: String) -> AbsolutePath {
    let xcodeprojName = "\(projectName).xcodeproj"
    return outputDir.appending(RelativePath(xcodeprojName))
}

/// Generates an Xcode project and all needed support files.  The .xcodeproj
/// wrapper directory is created to the path specified by `xcodeprojPath`
/// Returns the generated project.  All ancillary files will
/// be generated inside of the .xcodeproj wrapper directory.
@discardableResult
public func generate(
    projectName: String,
    xcodeprojPath: AbsolutePath,
    graph: PackageGraph,
    repositoryProvider: RepositoryProvider = GitRepositoryProvider(),
    options: XcodeprojOptions,
    diagnostics: DiagnosticsEngine
) throws -> Xcode.Project {
    diagnoseConditionalTargetDependencies(graph: graph, diagnostics: diagnostics)

    // Note that the output directory might be completely separate from the
    // path of the root package (which is where the sources live).

    let srcroot = graph.rootPackages[0].path

    // Determine the path of the scheme directory (it's inside the .xcodeproj).
    let schemesDir = xcodeprojPath.appending(components: "xcshareddata", "xcschemes")

    // Create the .xcodeproj wrapper directory.
    try makeDirectories(xcodeprojPath)
    try makeDirectories(schemesDir)

    let extraDirs: [AbsolutePath]
    var extraFiles = [AbsolutePath]()

    if options.addExtraFiles {
        // Find the paths of any extra directories that should be added as folder
        // references in the project.
        extraDirs = try findDirectoryReferences(path: srcroot)

        if try repositoryProvider.checkoutExists(at: srcroot) {
            let workingCheckout = try repositoryProvider.openCheckout(at: srcroot)
            extraFiles = try getExtraFilesFor(package: graph.rootPackages[0], in: workingCheckout)
        }
    } else {
        extraDirs = []
    }

    // FIXME: This could be more efficient by directly writing to a stream
    // instead of first creating a string.
    //
    /// Generate the contents of project.xcodeproj (inside the .xcodeproj).
    let project = try pbxproj(xcodeprojPath: xcodeprojPath, graph: graph, extraDirs: extraDirs, extraFiles: extraFiles, options: options, diagnostics: diagnostics)
    try open(xcodeprojPath.appending(component: "project.pbxproj")) { stream in
        // Serialize the project model we created to a plist, and return
        // its string description.
        let str = "// !$*UTF8*$!\n" + project.generatePlist().description
        stream(str)
    }

    try generateSchemes(
        graph: graph,
        container: xcodeprojPath.relative(to: srcroot).pathString,
        schemesDir: schemesDir,
        options: options,
        schemeContainer: xcodeprojPath.relative(to: srcroot).pathString
    )

    for target in graph.reachableTargets where target.type == .library || target.type == .test {
        ///// For framework targets, generate target.c99Name_Info.plist files in the
        ///// directory that Xcode project is generated
        let name = target.infoPlistFileName
        try open(xcodeprojPath.appending(RelativePath(name))) { print in
            print("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0">
                <dict>
                  <key>CFBundleDevelopmentRegion</key>
                  <string>en</string>
                  <key>CFBundleExecutable</key>
                  <string>$(EXECUTABLE_NAME)</string>
                  <key>CFBundleIdentifier</key>
                  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
                  <key>CFBundleInfoDictionaryVersion</key>
                  <string>6.0</string>
                  <key>CFBundleName</key>
                  <string>$(PRODUCT_NAME)</string>
                  <key>CFBundlePackageType</key>
                  <string>\(target.type == .test ? "BNDL" : "FMWK")</string>
                  <key>CFBundleShortVersionString</key>
                  <string>1.0</string>
                  <key>CFBundleSignature</key>
                  <string>????</string>
                  <key>CFBundleVersion</key>
                  <string>$(CURRENT_PROJECT_VERSION)</string>
                  <key>NSPrincipalClass</key>
                  <string></string>
                </dict>
                </plist>
                """)
        }
    }

    return project
}

private func diagnoseConditionalTargetDependencies(graph: PackageGraph, diagnostics: DiagnosticsEngine) {
    let targetsWithConditionalDependencies = graph.allTargets.lazy.filter { target in
        target.dependencies.contains { dependency in
            !dependency.conditions.isEmpty
        }
    }

    if !targetsWithConditionalDependencies.isEmpty {
        let targetNames = targetsWithConditionalDependencies.map { $0.name }.joined(separator: ", ")
        diagnostics.emit(warning: """
            Xcode project generation does not support conditional target dependencies, so the generated project might \
            not build successfully. The offending targets are: \(targetNames).
            """)
    }
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

    return rootDirectories.filter({
        if $0.suffix == ".xcodeproj" { return false }
        if $0.suffix == ".playground" { return false }
        if $0.basename.hasPrefix(".") { return false }
        if PackageBuilder.predefinedTestDirectories.contains($0.basename) { return false }
        return localFileSystem.isDirectory($0)
    })
}

func generateSchemes(
    graph: PackageGraph,
    container: String,
    schemesDir: AbsolutePath,
    options: XcodeprojOptions,
    schemeContainer: String
) throws {
    if options.useLegacySchemeGenerator {
        // The scheme acts like an aggregate target for all our targets it has all
        // tests associated so testing works. We suffix the name of this scheme with
        // -Package so its name doesn't collide with any products or target with
        // same name.
        let schemeName = "\(graph.rootPackages[0].name)-Package.xcscheme"
        try open(schemesDir.appending(RelativePath(schemeName))) { stream in
            legacySchemeGenerator(
                container: schemeContainer,
                graph: graph,
                codeCoverageEnabled: options.isCodeCoverageEnabled,
                printer: stream)
        }

        // We generate this file to ensure our main scheme is listed before any
        // inferred schemes Xcode may autocreate.
        try open(schemesDir.appending(component: "xcschememanagement.plist")) { print in
            print("""
                  <?xml version="1.0" encoding="UTF-8"?>
                  <plist version="1.0">
                  <dict>
                  <key>SchemeUserState</key>
                  <dict>
                  <key>\(schemeName)</key>
                  <dict></dict>
                  </dict>
                  <key>SuppressBuildableAutocreation</key>
                  <dict></dict>
                  </dict>
                  </plist>
                  """)
        }
    } else {
        try SchemesGenerator(
            graph: graph,
            container: schemeContainer,
            schemesDir: schemesDir,
            isCodeCoverageEnabled: options.isCodeCoverageEnabled,
            fs: localFileSystem
        ).generate()
    }
}

// Find and return non-source files in the source directories and root that should be added
// as a reference to the project.
func getExtraFilesFor(package: ResolvedPackage, in workingCheckout: WorkingCheckout) throws -> [AbsolutePath] {
    let srcroot = package.path
    var extraFiles = findNonSourceFiles(path: srcroot, toolsVersion: package.manifest.toolsVersion, recursively: false)

    for target in package.targets {
        let sourcesDirectory = target.sources.root
        if localFileSystem.isDirectory(sourcesDirectory) {
            let sourcesExtraFiles = findNonSourceFiles(path: sourcesDirectory, toolsVersion: package.manifest.toolsVersion, recursively: true)
            extraFiles.append(contentsOf: sourcesExtraFiles)
        }
    }

    // Return if we can't determine if the files are git ignored.
    guard let isIgnored = try? workingCheckout.areIgnored(extraFiles) else {
        return []
    }
    extraFiles = extraFiles.enumerated().filter({ !isIgnored[$0.offset] }).map({ $0.element })

    return extraFiles
}

/// Finds the non-source files from `path`
/// - parameters:
///   - path: The path of the directory to get the files from
///   - recursively: Specifies if the directory at `path` should be searched recursively
func findNonSourceFiles(path: AbsolutePath, toolsVersion: ToolsVersion, recursively: Bool) -> [AbsolutePath] {
    let filesFromPath: RecursibleDirectoryContentsGenerator?

    if recursively {
        filesFromPath = try? walk(path, recursing: { path in
            // Ignore any git submodule that we might encounter.
            let gitPath = path.appending(component: ".git")
            if localFileSystem.exists(gitPath) {
                return false
            }
            return recursively
        })
    } else {
        filesFromPath = try? walk(path, recursively: recursively)
    }

    return filesFromPath?.filter({
        if !localFileSystem.isFile($0) { return false }
        if $0.basename.hasPrefix(".") { return false }
        if $0.basename == "Package.resolved" { return false }
        if let `extension` = $0.extension, SupportedLanguageExtension.validExtensions(toolsVersion: toolsVersion).contains(`extension`) {
            return false
        }
        return true
    }) ?? []
}
