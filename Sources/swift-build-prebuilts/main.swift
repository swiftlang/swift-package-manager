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

var prebuiltRepos: [PrebuiltRepos.ID: PrebuiltRepos] = [
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
                        ],
                        artifacts: [
                            .init(platform: .macos_arm64, checksum: ""),
                            .init(platform: .macos_x86_64, checksum: ""),
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

let fm = FileManager.default
let args = ProcessInfo.processInfo.arguments

var stageDir = Path(fm.currentDirectoryPath + "/stage")
let swiftVersion = "\(SwiftVersion.current.major).\(SwiftVersion.current.minor)"

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
    default:
        fatalError("Unknown option \(arg)")
    }
    i += 1
}

print("Stage directory: \(stageDir)")
if stageDir.exists {
    try stageDir.remove()
}
try stageDir.mkdirs()
stageDir.cd()

for repo in prebuiltRepos.values {
    let repoDir = stageDir / repo.url.lastPathComponent
    let libDir = stageDir / "lib"
    let modulesDir = stageDir / "modules"
    let includesDir = stageDir / "include"
    let buildDir = repoDir / ".build" / "release"
    let srcModulesDir = buildDir / "Modules"

    try shell("git clone \(repo.url)")

    for version in repo.versions {
        repoDir.cd()
        try shell("git checkout \(version.tag)")

        var newLibraries: [Workspace.PrebuiltsManifest.Library] = []

        for library in version.manifest.libraries {
            // TODO: this is assuming products map to target names which is not always true
            try shell("swift package add-product \(library.name) --type static-library --targets \(library.products.joined(separator: " "))")

            var newArtifacts: [Workspace.PrebuiltsManifest.Library.Artifact] = []

            for artifact in library.artifacts {
                try libDir.mkdirs()
                try modulesDir.mkdirs()
                try includesDir.mkdirs()
                try shell("swift build -c release --arch \(artifact.platform.arch) --product \(library.name)")
                let lib = "lib\(library.name).a"
                try (buildDir / lib).cp(to: libDir / lib)

                for file in try srcModulesDir.ls() {
                    try (srcModulesDir / file).cp(to: modulesDir / file)
                }

                for cModule in library.cModules {
                    let cModuleDir = version.cModulePaths[cModule] ?? ["Sources", cModule]
                    let srcIncludeDir = repoDir / cModuleDir / "include"
                    let destIncludeDir = includesDir / cModule
                    try destIncludeDir.mkdirs()
                    for file in try srcIncludeDir.ls() {
                        try (srcIncludeDir / file).cp(to: destIncludeDir / file)
                    }
                }

                stageDir.cd()
                let zipFile = stageDir / "\(swiftVersion)-\(library.name)-\(artifact.platform).zip"
                let contentDirs = ["lib", "Modules"] + (library.cModules.isEmpty ? [] : ["include"])
                try zipFile.compress(contentDirs)
                repoDir.cd()

                newArtifacts.append(.init(platform: artifact.platform, checksum: try zipFile.checksum()))

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
            newLibraries.append(newLibrary)

            try shell("git reset --hard")
        }

        let newManifest = Workspace.PrebuiltsManifest(libraries: newLibraries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let manifestData = try encoder.encode(newManifest)
        let manifestFile = stageDir / "\(swiftVersion)-manifest.json"
        try manifestFile.write(manifestData)
    }
}

func shell(_ command: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw StringError("failed: \(command)")
    }
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

    private var path: String {
#if os(Windows)
        if let drive {
            return drive + ":\\" + components.joined(separator: "\\")
        } else {
            return "\\" + components.joined(separator: "\\")
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
        try fm.removeItem(atPath: path)
    }

    func mkdirs() throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func cd() {
        fm.changeCurrentDirectoryPath(path)
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

    func write(_ data: Data) throws {
        try data.write(to: url)
    }
}

extension Dictionary: @retroactive ExpressibleByArrayLiteral where Value: Identifiable, Key == Value.ID {
    public init(arrayLiteral elements: Value...) {
        self.init()
        for element in elements {
            self[element.id] = element
        }
    }
}
