/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic
import TSCUtility
import func POSIX.exit

import SPMPackageEditor
import class PackageModel.Manifest

enum ToolError: Error {
    case error(String)
    case noManifest
}

enum Mode: String {
    case addPackageDependency = "add-package"
    case addTarget = "add-target"
    case help
}

struct Options {
    struct AddPackageDependency {
        let url: String
    }
    struct AddTarget {
        let name: String
    }
    var dataPath: AbsolutePath = AbsolutePath("/tmp")
    var addPackageDependency: AddPackageDependency?
    var addTarget: AddTarget?
    var mode = Mode.help
}

/// Finds the Package.swift manifest file in the current working directory.
func findPackageManifest() -> AbsolutePath? {
    guard let cwd = localFileSystem.currentWorkingDirectory else {
        return nil
    }

    let manifestPath = cwd.appending(component: Manifest.filename)
    return localFileSystem.isFile(manifestPath) ? manifestPath : nil
}

final class PackageIndex {

    struct Entry: Codable {
        let name: String
        let url: String
    }

    // Name -> URL
    private(set) var index: [String: String]

    init() throws {
        index = [:]

        let indexFile = localFileSystem.homeDirectory.appending(components: ".swiftpm", "package-mapping.json")
        guard localFileSystem.isFile(indexFile) else {
            return
        }

        let bytes = try localFileSystem.readFileContents(indexFile).contents
        let entries = try JSONDecoder().decode(Array<Entry>.self, from: Data(bytes: bytes, count: bytes.count))

        index = Dictionary(uniqueKeysWithValues: entries.map{($0.name, $0.url)})
    }
}

do {
    let binder = ArgumentBinder<Options>()

    let parser = ArgumentParser(
        usage: "subcommand",
        overview: "Tool for editing the Package.swift manifest file")

    // Add package dependency.
    let packageDependencyParser = parser.add(subparser: Mode.addPackageDependency.rawValue, overview: "Add a new package dependency")
    binder.bind(
        positional: packageDependencyParser.add(positional: "package-url", kind: String.self, usage: "Dependency URL"),
        to: { $0.addPackageDependency = Options.AddPackageDependency(url: $1) })

    // Add Target.
    let addTargetParser = parser.add(subparser: Mode.addTarget.rawValue, overview: "Add a new target")
    binder.bind(
        positional: addTargetParser.add(positional: "target-name", kind: String.self, usage: "Target name"),
        to: { $0.addTarget = Options.AddTarget(name: $1) })

    // Bind the mode.
    binder.bind(
        parser: parser,
        to: { $0.mode = Mode(rawValue: $1)! })

    // Parse the options.
    var options = Options()
    let result = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    try binder.fill(parseResult: result, into: &options)

    // Find the Package.swift file in cwd.
    guard let manifest = findPackageManifest() else {
        throw ToolError.noManifest
    }
    options.dataPath = (localFileSystem.currentWorkingDirectory ?? AbsolutePath("/tmp")).appending(component: ".build")

    switch options.mode {
    case .addPackageDependency:
        var url = options.addPackageDependency!.url
        url = try PackageIndex().index[url] ?? url

        let editor = try PackageEditor(buildDir: options.dataPath)
        try editor.addPackageDependency(options: .init(manifestPath: manifest, url: url, requirement: nil))

    case .addTarget:
        let targetOptions = options.addTarget!

        let editor = try PackageEditor(buildDir: options.dataPath)
        try editor.addTarget(options: .init(manifestPath: manifest, targetName: targetOptions.name, targetType: .regular))

    case .help:
        parser.printUsage(on: stdoutStream)
    }

} catch {
    stderrStream <<< String(describing: error) <<< "\n"
    stderrStream.flush()
    POSIX.exit(1)
}
