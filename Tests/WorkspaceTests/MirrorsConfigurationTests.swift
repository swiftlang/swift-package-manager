//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import Workspace
import Testing
import struct TSCBasic.ByteString

import _InternalTestSupport

fileprivate struct MirrorsConfigurationTests {
    @Test
    func loadingSchema1() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try fs.createDirectory(configFile.parentDirectory)
        try fs.writeFileContents(
            configFile,
            string: """
            {
              "object": [
                {
                  "mirror": "\(mirrorURL)",
                  "original": "\(originalURL)"
                }
              ],
              "version": 1
            }
            """
        )

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)
        let mirrors = try config.get()

        #expect(mirrors.mirror(for: originalURL) == mirrorURL)
        #expect(mirrors.original(for: mirrorURL) == originalURL)
    }

    @Test
    func throwsWhenNotFound() throws {
        let gitUrl = "https://github.com/apple/swift-argument-parser.git"
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)
        let mirrors = try config.get()

        #expect(throws: StringError("Mirror not found for '\(gitUrl)'")) {
            try mirrors.unset(originalOrMirror: gitUrl)
        }
    }

    @Test
    func deleteWhenEmpty() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        try config.apply{ _ in }
        #expect(!fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try config.apply{ mirrors in
            try mirrors.set(mirror: mirrorURL, for: originalURL)
        }
        #expect(fs.exists(configFile))

        try config.apply{ mirrors in
            try mirrors.unset(originalOrMirror: originalURL)
        }
        #expect(!fs.exists(configFile))
    }

    @Test
    func dontDeleteWhenEmpty() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: false)

        try config.apply{ _ in }
        #expect(!fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try config.apply{ mirrors in
            try mirrors.set(mirror: mirrorURL, for: originalURL)
        }
        #expect(fs.exists(configFile))

        try config.apply{ mirrors in
            try mirrors.unset(originalOrMirror: originalURL)
        }
        #expect(fs.exists(configFile))
        #expect(try config.get().isEmpty)
    }

    @Test
    func localAndShared() throws {
        let fs = InMemoryFileSystem()
        let localConfigFile = AbsolutePath("/config/local-mirrors.json")
        let sharedConfigFile = AbsolutePath("/config/shared-mirrors.json")

        let config = try Workspace.Configuration.Mirrors(
            fileSystem: fs,
            localMirrorsFile: localConfigFile,
            sharedMirrorsFile: sharedConfigFile
        )

        // first write to shared location

        let original1URL = "https://github.com/apple/swift-argument-parser.git"
        let mirror1URL = "https://github.com/mona/swift-argument-parser.git"

        try config.applyShared { mirrors in
            try mirrors.set(mirror: mirror1URL, for: original1URL)
        }

        #expect(config.mirrors.count == 1)
        #expect(config.mirrors.mirror(for: original1URL) == mirror1URL)
        #expect(config.mirrors.original(for: mirror1URL) == original1URL)

        // now write to local location

        let original2URL = "https://github.com/apple/swift-nio.git"
        let mirror2URL = "https://github.com/mona/swift-nio.git"

        try config.applyLocal { mirrors in
            try mirrors.set(mirror: mirror2URL, for: original2URL)
        }

        #expect(config.mirrors.count == 1)
        #expect(config.mirrors.mirror(for: original2URL) == mirror2URL)
        #expect(config.mirrors.original(for: mirror2URL) == original2URL)

        // should not see the shared any longer
        #expect(config.mirrors.mirror(for: original1URL) == nil)
        #expect(config.mirrors.original(for: mirror1URL) == nil)
    }

    // MARK: - Deterministic Output Tests

    @Test
    func deterministicJSONOutputWithMultipleMirrors() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        // Add multiple mirrors in a specific order
        let mirrorsToAdd = [
            ("https://github.com/zebra/package-z.git", "https://mirror.com/zebra/package-z.git"),
            ("https://github.com/apple/swift-argument-parser.git", "https://mirror.com/apple/swift-argument-parser.git"),
            ("https://github.com/mona/swift-nio.git", "https://mirror.com/mona/swift-nio.git"),
            ("https://github.com/beta/package-b.git", "https://mirror.com/beta/package-b.git")
        ]

        try config.apply { mirrors in
            for (original, mirror) in mirrorsToAdd {
                try mirrors.set(mirror: mirror, for: original)
            }
        }

        // Read the file content multiple times and verify it's identical
        let content1 = try fs.readFileContents(configFile)
        let content2 = try fs.readFileContents(configFile)
        #expect(content1 == content2)

        // Parse the JSON and verify it's properly structured
        let jsonObject = try JSONSerialization.jsonObject(with: Data(content1.contents), options: [])
        guard let json = jsonObject as? [String: Any],
              let version = json["version"] as? Int,
              let objects = json["object"] as? [[String: String]] else {
            throw StringError("Invalid JSON structure")
        }

        #expect(version == 1)
        #expect(objects.count == mirrorsToAdd.count)

        // Verify the objects are sorted deterministically
        let sortedObjects = objects.sorted { $0["original"]! < $1["original"]! }
        #expect(objects == sortedObjects, "Mirror objects should be sorted deterministically by original URL")
    }

    @Test
    func consistentOrderingAcrossMultipleSaves() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        let mirrorsToAdd = [
            ("https://github.com/third/package.git", "https://mirror3.com/third/package.git"),
            ("https://github.com/first/package.git", "https://mirror1.com/first/package.git"),
            ("https://github.com/second/package.git", "https://mirror2.com/second/package.git")
        ]

        // Perform multiple save operations and collect file contents
        var fileContents: [ByteString] = []

        for iteration in 0..<5 {
            // Clear the file
            if fs.exists(configFile) {
                try fs.removeFileTree(configFile)
            }

            // Add mirrors in different orders each time
            let shuffledMirrors = iteration % 2 == 0 ? mirrorsToAdd : mirrorsToAdd.reversed()

            try config.apply { mirrors in
                for (original, mirror) in shuffledMirrors {
                    try mirrors.set(mirror: mirror, for: original)
                }
            }

            let content = try fs.readFileContents(configFile)
            fileContents.append(content)
        }

        // All file contents should be identical regardless of insertion order
        for i in 1..<fileContents.count {
            #expect(fileContents[0] == fileContents[i],
                    "File content should be identical across saves (iteration \(i))")
        }
    }

    @Test
    func sameInputProducesIdenticalFileContents() throws {
        let fs1 = InMemoryFileSystem()
        let fs2 = InMemoryFileSystem()
        let configFile1 = AbsolutePath("/config/mirrors1.json")
        let configFile2 = AbsolutePath("/config/mirrors2.json")

        let config1 = Workspace.Configuration.MirrorsStorage(path: configFile1, fileSystem: fs1, deleteWhenEmpty: true)
        let config2 = Workspace.Configuration.MirrorsStorage(path: configFile2, fileSystem: fs2, deleteWhenEmpty: true)

        // Identical mirror configurations
        let mirrors = [
            ("https://github.com/user/repo1.git", "https://mirror.example.com/user/repo1.git"),
            ("https://github.com/user/repo2.git", "https://mirror.example.com/user/repo2.git"),
            ("https://github.com/org/project.git", "https://private-mirror.com/org/project.git")
        ]

        // Apply same configuration to both
        try config1.apply { mirrorsConfig in
            for (original, mirror) in mirrors {
                try mirrorsConfig.set(mirror: mirror, for: original)
            }
        }

        try config2.apply { mirrorsConfig in
            for (original, mirror) in mirrors {
                try mirrorsConfig.set(mirror: mirror, for: original)
            }
        }

        let content1 = try fs1.readFileContents(configFile1)
        let content2 = try fs2.readFileContents(configFile2)

        #expect(content1 == content2, "Identical mirror configurations should produce identical file contents")
    }

    @Test
    func incrementalMirrorAdditionPreservesOrder() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        // First, add initial mirrors
        let initialMirrors = [
            ("https://github.com/zebra/zoo.git", "https://mirror.com/zebra/zoo.git"),
            ("https://github.com/apple/swift.git", "https://mirror.com/apple/swift.git"),
            ("https://github.com/microsoft/vscode.git", "https://mirror.com/microsoft/vscode.git")
        ]

        try config.apply { mirrors in
            for (original, mirror) in initialMirrors {
                try mirrors.set(mirror: mirror, for: original)
            }
        }

        // Capture the initial state
        let initialContent = try fs.readFileContents(configFile)
        let initialJson = try JSONSerialization.jsonObject(with: Data(initialContent.contents), options: [])
        guard let initialDict = initialJson as? [String: Any],
              let initialObjects = initialDict["object"] as? [[String: String]] else {
            throw StringError("Invalid initial JSON structure")
        }
        let initialOriginals = initialObjects.compactMap { $0["original"] }

        // Add more mirrors to the existing configuration
        let additionalMirrors = [
            ("https://github.com/beta/test.git", "https://mirror.com/beta/test.git"),
            ("https://github.com/gamma/gamma.git", "https://mirror.com/gamma/gamma.git")
        ]

        try config.apply { mirrors in
            for (original, mirror) in additionalMirrors {
                try mirrors.set(mirror: mirror, for: original)
            }
        }

        // Verify the final state maintains deterministic order
        let finalContent = try fs.readFileContents(configFile)
        let finalJson = try JSONSerialization.jsonObject(with: Data(finalContent.contents), options: [])
        guard let finalDict = finalJson as? [String: Any],
              let finalObjects = finalDict["object"] as? [[String: String]] else {
            throw StringError("Invalid final JSON structure")
        }
        let finalOriginals = finalObjects.compactMap { $0["original"] }

        // Verify all expected mirrors are present
        let allExpectedOriginals = (initialMirrors + additionalMirrors).map { $0.0 }
        #expect(finalOriginals.count == allExpectedOriginals.count)
        for expectedOriginal in allExpectedOriginals {
            #expect(finalOriginals.contains(expectedOriginal), "All mirrors should be present")
        }

        // Verify the order is deterministic (alphabetical)
        let sortedExpected = allExpectedOriginals.sorted()
        #expect(finalOriginals == sortedExpected, "Final mirror order should be deterministic (alphabetical)")

        // Test that adding the same configuration again produces identical results
        try config.apply { mirrors in
            for (original, mirror) in additionalMirrors {
                try mirrors.set(mirror: mirror, for: original) // Re-adding same mirrors
            }
        }

        let duplicateAddContent = try fs.readFileContents(configFile)
        #expect(finalContent == duplicateAddContent, "Re-adding same mirrors should produce identical content")
    }

    @Test
    func deterministicOutputForEdgeCases() throws {
        let configFile = AbsolutePath("/config/edge-cases-mirrors.json")
        let fs = InMemoryFileSystem()

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: false)

        // Test empty configuration - need to add at least one mirror first to create the file
        try config.apply { mirrors in
            try mirrors.set(mirror: "https://temp.com/temp.git", for: "https://github.com/temp.git")
        }
        try config.apply { mirrors in
            try mirrors.unset(originalOrMirror: "https://github.com/temp.git")  // Remove it to make empty
        }
        #expect(fs.exists(configFile))
        let emptyContent1 = try fs.readFileContents(configFile)

        // Apply empty configuration again
        try config.apply { _ in }
        let emptyContent2 = try fs.readFileContents(configFile)
        #expect(emptyContent1 == emptyContent2, "Empty configurations should produce identical output")

        // Test single mirror
        try config.apply { mirrors in
            try mirrors.set(mirror: "https://mirror.com/single.git", for: "https://github.com/single.git")
        }
        let singleContent1 = try fs.readFileContents(configFile)

        // Clear and add the same single mirror again
        try config.apply { mirrors in
            try mirrors.unset(originalOrMirror: "https://github.com/single.git")
            try mirrors.set(mirror: "https://mirror.com/single.git", for: "https://github.com/single.git")
        }
        let singleContent2 = try fs.readFileContents(configFile)
        #expect(singleContent1 == singleContent2, "Single mirror configurations should produce identical output")
    }

    @Test
    func jsonOutputOrderingIsAlphabetical() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        // Add mirrors in non-alphabetical order
        let mirrors = [
            ("https://github.com/zebra/zoo.git", "https://mirror.com/zebra/zoo.git"),
            ("https://github.com/apple/swift.git", "https://mirror.com/apple/swift.git"),
            ("https://github.com/microsoft/vscode.git", "https://mirror.com/microsoft/vscode.git"),
            ("https://github.com/beta/test.git", "https://mirror.com/beta/test.git")
        ]

        try config.apply { mirrorsConfig in
            for (original, mirror) in mirrors {
                try mirrorsConfig.set(mirror: mirror, for: original)
            }
        }

        let content = try fs.readFileContents(configFile)
        let jsonObject = try JSONSerialization.jsonObject(with: Data(content.contents), options: [])

        guard let json = jsonObject as? [String: Any],
              let objects = json["object"] as? [[String: String]] else {
            throw StringError("Invalid JSON structure")
        }

        // Extract the original URLs and verify they are in alphabetical order
        let originalUrls = objects.compactMap { $0["original"] }
        let sortedUrls = originalUrls.sorted()

        #expect(originalUrls == sortedUrls, "Original URLs should be in alphabetical order in JSON output")

        // Verify all expected mirrors are present
        #expect(originalUrls.count == mirrors.count)
        for (expectedOriginal, _) in mirrors {
            #expect(originalUrls.contains(expectedOriginal), "All mirrors should be present in output")
        }
    }
}
