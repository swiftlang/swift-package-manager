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

import Basics
import _InternalTestSupport
import Workspace
import Testing

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

        try config.apply { _ in }
        #expect(!fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try config.apply { mirrors in
            try mirrors.set(mirror: mirrorURL, for: originalURL)
        }
        #expect(fs.exists(configFile))

        try config.apply { mirrors in
            try mirrors.unset(originalOrMirror: originalURL)
        }
        #expect(!fs.exists(configFile))
    }

    @Test
    func dontDeleteWhenEmpty() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/mirrors.json")

        let config = Workspace.Configuration.MirrorsStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: false)

        try config.apply { _ in }
        #expect(!fs.exists(configFile))

        let originalURL = "https://github.com/apple/swift-argument-parser.git"
        let mirrorURL = "https://github.com/mona/swift-argument-parser.git"

        try config.apply { mirrors in
            try mirrors.set(mirror: mirrorURL, for: originalURL)
        }
        #expect(fs.exists(configFile))

        try config.apply { mirrors in
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
}
