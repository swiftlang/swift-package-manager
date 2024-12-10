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

import Basics
import Foundation
import TSCBasic
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

let fm = FileManager.default
let args = ProcessInfo.processInfo.arguments

let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

var stageDir = Path(fm.currentDirectoryPath + "/stage")

var docker = false
var dockeronly = false
var dockercmd = "docker"
let dockerImageRoot = "swiftlang/swift:nightly-"

var i = 1
while i < args.count {
    let arg = args[i]
    switch arg {
    case "--stage-dir":
        if i + 1 < args.count {
            stageDir = .init(args[i + 1])
            i += 1
        } else {
            fatalError("Stage directory not specified")
        }
    case "--docker":
        docker = true
    case "--docker-only":
        docker = true
        dockeronly = true
    case "--docker-command":
        if i + 1 < args.count {
            dockercmd = args[i + 1]
            i += 1
        } else {
            fatalError("Docker command not specified")
        }
    default:
        fatalError("Unknown option \(arg)")
    }
    i += 1
}

print("Stage directory: \(stageDir)")
try stageDir.remove()
try stageDir.mkdirs()
stageDir.cd()

for repo in prebuiltRepos.values {
    let repoDir = stageDir / repo.url.lastPathComponent
    let libDir = stageDir / "lib"
    let modulesDir = stageDir / "modules"
    let includesDir = stageDir / "include"
    let scratchDir = repoDir / ".build"
    let buildDir = scratchDir / "release"
    let srcModulesDir = buildDir / "Modules"

    try shell("git clone \(repo.url)")

    for version in repo.versions {
        repoDir.cd()
        try shell("git checkout \(version.tag)")

        var newLibraries: IdentifiableSet<Workspace.PrebuiltsManifest.Library> = []

        for library in version.manifest.libraries {
            // TODO: this is assuming products map to target names which is not always true
            try shell("swift package add-product \(library.name) --type static-library --targets \(library.products.joined(separator: " "))")

            var newArtifacts: [Workspace.PrebuiltsManifest.Library.Artifact] = []

            for platform in Workspace.PrebuiltsManifest.Platform.allCases {
                guard canBuild(platform) else {
                    continue
                }

                try libDir.mkdirs()
                try modulesDir.mkdirs()
                try includesDir.mkdirs()

                // Clean out the scratch dir
                try scratchDir.remove()

                // Build
                var cmd = ""
                if let dockerTag = platform.dockerTag, let dockerPlatform = platform.arch.dockerPlatform {
                    cmd += "\(dockercmd) run --rm --platform \(dockerPlatform) -v \(repoDir):\(repoDir) -w \(repoDir) \(dockerImageRoot)\(dockerTag) "
                }
                cmd += "swift build -c release --arch \(platform.arch) --product \(library.name)"
                try shell(cmd)

                // Copy the library to staging
                let lib = "lib\(library.name).a"
                try (buildDir / lib).cp(to: libDir / lib)

                // Copy the swiftmodules
                for file in try srcModulesDir.ls() {
                    try (srcModulesDir / file).cp(to: modulesDir / file)
                }

                // Copy the C module headers
                for cModule in library.cModules {
                    let cModuleDir = version.cModulePaths[cModule] ?? ["Sources", cModule]
                    let srcIncludeDir = repoDir / cModuleDir / "include"
                    let destIncludeDir = includesDir / cModule
                    try destIncludeDir.mkdirs()
                    for file in try srcIncludeDir.ls() {
                        try (srcIncludeDir / file).cp(to: destIncludeDir / file)
                    }
                }

                // Zip it up
                stageDir.cd()
                let zipFile = stageDir / "\(swiftVersion)-\(library.name)-\(platform).zip"
                let contentDirs = ["lib", "Modules"] + (library.cModules.isEmpty ? [] : ["include"])
                try zipFile.compress(contentDirs)
                repoDir.cd()

                newArtifacts.append(.init(platform: platform, checksum: try zipFile.checksum()))

                try libDir.remove()
                try modulesDir.remove()
                try includesDir.remove()
            }

            let newLibrary = Workspace.PrebuiltsManifest.Library(
                name: library.name,
                products: library.products,
                cModules: library.cModules,
                artifacts: newArtifacts
            )
            newLibraries.insert(newLibrary)

            try shell("git reset --hard")
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
        let manifestFile = stageDir / "\(swiftVersion)-manifest.json"
        try manifestFile.write(manifestData)
    }
}

func canBuild(_ platform: Workspace.PrebuiltsManifest.Platform) -> Bool {
    if dockeronly {
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

func shell(_ command: String) throws {
    let process = Process()
#if os(Windows)
    process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
    process.arguments = ["/c", command]
#else
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
#endif
    print("Running:", command)
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw StringError("failed: \(command)")
    }
}

func downloadManifest(version: PrebuiltRepos.Version) async throws -> Workspace.PrebuiltsManifest? {
    let manifestFile = swiftVersion + "-manifest.json"
    let destination = await stageDir / manifestFile
    if destination.exists {
        do {
            return try JSONDecoder().decode(
                Workspace.PrebuiltsManifest.self,
                from: try destination.read()
            )
        } catch {
            // redownload it
            try destination.remove()
        }
    }
    let manifestURL = manifestHost.appending(components: version.tag, manifestFile)
    print("Downloading:", manifestURL.absoluteString)
    let httpClient = HTTPClient()
    var headers = HTTPClientHeaders()
    headers.add(name: "Accept", value: "application/json")
    var request = HTTPClient.Request(kind: .generic(.get), url: manifestURL)
    request.options.validResponseCodes = [200]

    let response = try await httpClient.execute(request) { _, _ in }
    if let body = response.body {
        return try JSONDecoder().decode(
            Workspace.PrebuiltsManifest.self,
            from: body
        )
    }

    return nil
}

// Path utility
struct Path: CustomStringConvertible {
    private let drive: Substring?
    private let components: [Substring]

    private static var separator: String {
#if os(Windows)
            "\\"
#else
            "/"
#endif
    }

    private init(drive: Substring?, components: [Substring]) {
        self.drive = drive
        self.components = components
    }

    init(_ value: String) {
#if os(Windows)
        let winValue = value.replacingOccurrences(of: "/", with: "\\")
        let driveComps = winValue.split(separator: ":")
        if driveComps.count > 1 {
            self.drive = driveComps[0]
            self.components = driveComps[1].split(separator: "\\")
            return
        }
#endif
        self.drive = nil
        self.components = value.split(separator: Self.separator)
    }

    var path: String {
#if os(Windows)
        if let drive {
            return drive + ":\\" + components.joined(separator: "\\")
        }
#endif
        return Self.separator + components.joined(separator: Self.separator)
    }

    var description: String {
        path
    }

    static func /(lhs: Path, rhs: String) -> Path {
        .init(drive: lhs.drive, components: lhs.components + [rhs[...]])
    }

    static func /(lhs: Path, rhs: [String]) -> Path {
        .init(drive: lhs.drive, components: lhs.components + rhs.map({ $0[...] }))
    }

    var basename: Substring {
        components.last ?? Self.separator[...]
    }

    var exists: Bool {
        fm.fileExists(atPath: path)
    }

    func remove() throws {
        guard exists else {
            // Already gone
            return
        }
        try fm.removeItem(atPath: path)
    }

    func mkdirs() throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func cd() {
        _ = fm.changeCurrentDirectoryPath(path)
    }

    func cp(to other: Path) throws {
        try fm.copyItem(atPath: path, toPath: other.path)
    }

    func ls() throws -> [String] {
        try fm.contentsOfDirectory(atPath: path)
    }

    func compress(_ files: [String]) throws {
#if os(Windows)
        try shell("tar -acf \(path) \(files.joined(separator: " "))")
#else
        try shell("zip -r \(path) \(files.joined(separator: " "))")
#endif
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    func checksum() throws -> String {
        let contents = try ByteString(Data(contentsOf: self.url))
        return SHA256().hash(contents).hexadecimalRepresentation
    }

    func read() throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data) throws {
        try data.write(to: url)
    }
}

extension Workspace.PrebuiltsManifest.Platform {
    var dockerTag: String? {
        guard docker else {
            return nil
        }

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
