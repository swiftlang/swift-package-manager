//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Checkout supported versions of the prebuilts, build them, package up the zip and update the manifest file.

// Ideally this would be a script, however until we have package dependencies
// for scripts, this will need to be a part of the package. But this is why it's
// reading like a script

import ArgumentParser
import Basics
import Foundation
import struct TSCBasic.ByteString
import struct TSCBasic.SHA256
import Workspace

struct PrebuiltRepos: Identifiable {
    let url: URL
    let versions: [Version]

    var id: URL { url }

    struct Version: Identifiable {
        let tag: String
        let manifest: Workspace.PrebuiltsManifest
        let cModulePaths: [String: [String]]

        var id: String { tag }
    }
}

var prebuiltRepos: IdentifiableSet<PrebuiltRepos> = [
    .init(
        url: .init(string: "https://github.com/swiftlang/swift-syntax")!,
        versions: [
            .init(
                tag:"600.0.1",
                manifest: .init(libraries: [
                    .init(
                        name: "MacroSupport",
                        products: [
                            "SwiftSyntaxMacrosTestSupport",
                            "SwiftCompilerPlugin",
                            "SwiftSyntaxMacros"
                        ],
                        cModules: [
                            "_SwiftSyntaxCShims",
                        ]
                    ),

                ]),
                cModulePaths: [
                    "_SwiftSyntaxCShims": ["Sources", "_SwiftSyntaxCShims"]
                ]
            ),
        ]
    ),
]

let manifestHost = URL(string: "https://github.com/dschaefer2/swift-syntax/releases/download")!
let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"
let dockerImageRoot = "swiftlang/swift:nightly-"

@main
struct BuildPrebuilts: AsyncParsableCommand {
    @Option(help: "The directory to generate the artifacts to")
    var stageDir = try! AbsolutePath(validating: FileManager.default.currentDirectoryPath).appending("stage")

    @Flag(help: "Whether to build artifacts using docker")
    var docker = false

    @Flag(help: "Whether to build artifacts using docker only")
    var dockerOnly = false

    @Option(help: "The command to use for docker")
    var dockerCommand: String = "docker"

    mutating func run() async throws {
        let fm = FileManager.default

        print("Stage directory: \(stageDir)")
        try fm.removeItem(atPath: stageDir.pathString)
        try fm.createDirectory(atPath: stageDir.pathString, withIntermediateDirectories: true)
        _ = fm.changeCurrentDirectoryPath(stageDir.pathString)

        for repo in prebuiltRepos.values {
            let repoDir = stageDir.appending(repo.url.lastPathComponent)
            let libDir = stageDir.appending("lib")
            let modulesDir = stageDir.appending("modules")
            let includesDir = stageDir.appending("include")
            let scratchDir = repoDir.appending(".build")
            let buildDir = scratchDir.appending("release")
            let srcModulesDir = buildDir.appending("Modules")

            try await shell("git clone \(repo.url)")

            for version in repo.versions {
                _ = fm.changeCurrentDirectoryPath(repoDir.pathString)
                try await shell("git checkout \(version.tag)")

                var newLibraries: IdentifiableSet<Workspace.PrebuiltsManifest.Library> = []

                for library in version.manifest.libraries {
                    // TODO: this is assuming products map to target names which is not always true
                    try await shell("swift package add-product \(library.name) --type static-library --targets \(library.products.joined(separator: " "))")

                    var newArtifacts: [Workspace.PrebuiltsManifest.Library.Artifact] = []

                    for platform in Workspace.PrebuiltsManifest.Platform.allCases {
                        guard canBuild(platform) else {
                            continue
                        }

                        try fm.createDirectory(atPath: libDir.pathString, withIntermediateDirectories: true)
                        try fm.createDirectory(atPath: modulesDir.pathString, withIntermediateDirectories: true)
                        try fm.createDirectory(atPath: includesDir.pathString, withIntermediateDirectories: true)

                        // Clean out the scratch dir
                        if fm.fileExists(atPath: scratchDir.pathString) {
                            try fm.removeItem(atPath: scratchDir.pathString)
                        }

                        // Build
                        var cmd = ""
                        if docker, let dockerTag = platform.dockerTag, let dockerPlatform = platform.arch.dockerPlatform {
                            cmd += "\(dockerCommand) run --rm --platform \(dockerPlatform) -v \(repoDir):\(repoDir) -w \(repoDir) \(dockerImageRoot)\(dockerTag) "
                        }
                        cmd += "swift build -c release --arch \(platform.arch) --product \(library.name)"
                        try await shell(cmd)

                        // Copy the library to staging
                        let lib = "lib\(library.name).a"
                        try fm.copyItem(atPath: buildDir.appending(lib).pathString, toPath: libDir.appending(lib).pathString)

                        // Copy the swiftmodules
                        for file in try fm.contentsOfDirectory(atPath: srcModulesDir.pathString) {
                            try fm.copyItem(atPath: srcModulesDir.appending(file).pathString, toPath: modulesDir.appending(file).pathString)
                        }

                        // Copy the C module headers
                        for cModule in library.cModules {
                            let cModuleDir = version.cModulePaths[cModule] ?? ["Sources", cModule]
                            let srcIncludeDir = repoDir.appending(components: cModuleDir).appending("include")
                            let destIncludeDir = includesDir.appending(cModule)
                            try fm.createDirectory(atPath: destIncludeDir.pathString, withIntermediateDirectories: true)
                            for file in try fm.contentsOfDirectory(atPath: srcIncludeDir.pathString) {
                                try fm.copyItem(atPath: srcIncludeDir.appending(file).pathString, toPath: destIncludeDir.appending(file).pathString)
                            }
                        }

                        // Zip it up
                        _ = fm.changeCurrentDirectoryPath(stageDir.pathString)
                        let zipFile = stageDir.appending("\(swiftVersion)-\(library.name)-\(platform).zip")
                        let contentDirs = ["lib", "Modules"] + (library.cModules.isEmpty ? [] : ["include"])
#if os(Windows)
                        try await shell("tar -acf \(zipFile.pathString) \(contentDirs.joined(separator: " "))")
#else
                        try await shell("zip -r \(zipFile.pathString) \(contentDirs.joined(separator: " "))")
#endif

                        _ = fm.changeCurrentDirectoryPath(repoDir.pathString)
                        let contents = try ByteString(Data(contentsOf: zipFile.asURL))
                        let checksum = SHA256().hash(contents).hexadecimalRepresentation

                        newArtifacts.append(.init(platform: platform, checksum: checksum))

                        try fm.removeItem(atPath: libDir.pathString)
                        try fm.removeItem(atPath: modulesDir.pathString)
                        try fm.removeItem(atPath: includesDir.pathString)
                    }

                    let newLibrary = Workspace.PrebuiltsManifest.Library(
                        name: library.name,
                        products: library.products,
                        cModules: library.cModules,
                        artifacts: newArtifacts
                    )
                    newLibraries.insert(newLibrary)

                    try await shell("git reset --hard")
                }

                if let oldManifest = try await downloadManifest(version: version) {
                    // Add in elements from the old manifest we haven't generated
                    for library in oldManifest.libraries {
                        if var newLibrary = newLibraries[library.name] {
                            var newArtifacts = IdentifiableSet<Workspace.PrebuiltsManifest.Library.Artifact>(newLibrary.artifacts)
                            for oldArtifact in library.artifacts {
                                if !newArtifacts.contains(id: oldArtifact.id) {
                                    newArtifacts.insert(oldArtifact)
                                }
                            }
                            newLibrary.artifacts = .init(newArtifacts.values)
                            newLibraries.insert(newLibrary)
                        } else {
                            newLibraries.insert(library)
                        }
                    }
                }
                let newManifest = Workspace.PrebuiltsManifest(libraries: .init(newLibraries.values))

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let manifestData = try encoder.encode(newManifest)
                let manifestFile = stageDir.appending("\(swiftVersion)-manifest.json")
                try manifestData.write(to: manifestFile.asURL)
            }
        }
    }

    func canBuild(_ platform: Workspace.PrebuiltsManifest.Platform) -> Bool {
        if dockerOnly {
            return platform.os == .linux
        }
#if os(macOS)
        if platform.os == .macos {
            return true
        }
#elseif os(Windows)
        if platform.os == .windows {
            return true
        }
#endif
        return docker && platform.os == .linux
    }

    func shell(_ command: String) async throws {
#if os(Windows)
        let arguments = ["C:\\Windows\\System32\\cmd.exe", "/c", command]
#else
        let arguments = ["/bin/bash", "-c", command]
#endif
        let process = AsyncProcess(
            arguments: arguments,
            outputRedirection: .none
        )
        print("Running:", command)
        try process.launch()
        let result = try await process.waitUntilExit()
        switch result.exitStatus {
        case .terminated(code: let code):
            if code != 0 {
                throw StringError("Command exited with code \(code): \(command)")
            }
#if os(Windows)
        case .abnormal(exception: let exception):
            throw StringError("Command threw exception \(exception): \(command)")
#else
        case .signalled(signal: let signal):
            throw StringError("Command exited on signal \(signal): \(command)")
#endif
        }
    }

    func downloadManifest(version: PrebuiltRepos.Version) async throws -> Workspace.PrebuiltsManifest? {
        let fm = FileManager.default
        let manifestFile = swiftVersion + "-manifest.json"
        let destination = stageDir.appending(manifestFile)
        if fm.fileExists(atPath: destination.pathString) {
            do {
                return try JSONDecoder().decode(
                    Workspace.PrebuiltsManifest.self,
                    from: Data(contentsOf: destination.asURL)
                )
            } catch {
                // redownload it
                try fm.removeItem(atPath: destination.pathString)
            }
        }
        let manifestURL = manifestHost.appending(components: version.tag, manifestFile)
        print("Downloading:", manifestURL.absoluteString)
        let httpClient = HTTPClient()
        var headers = HTTPClientHeaders()
        headers.add(name: "Accept", value: "application/json")
        var request = HTTPClient.Request(kind: .generic(.get), url: manifestURL)
        request.options.validResponseCodes = [200]

        let response = try? await httpClient.execute(request) { _, _ in }
        if let body = response?.body {
            return try JSONDecoder().decode(
                Workspace.PrebuiltsManifest.self,
                from: body
            )
        }

        return nil
    }
}

extension Workspace.PrebuiltsManifest.Platform {
    var dockerTag: String? {
        switch self {
        case .ubuntu_jammy_aarch64, .ubuntu_jammy_x86_64:
            return "jammy"
        case .ubuntu_focal_aarch64, .ubuntu_focal_x86_64:
            return "focal"
        case .rhel_ubi9_aarch64, .rhel_ubi9_x86_64:
            return "rhel-ubi9"
        case .amazonlinux2_aarch64, .amazonlinux2_x86_64:
            return "amazonlinux2"
        default:
            return nil
        }
    }
}

extension Workspace.PrebuiltsManifest.Platform.Arch {
    var dockerPlatform: String? {
        switch self {
        case .aarch64:
            return "linux/arm64"
        case .x86_64:
            return "linux/amd64"
        }
    }
}

extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        try? self.init(validating: argument)
    }
}
