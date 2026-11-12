//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import SPMBuildCore
import Testing

@Suite(.tags(.TestSize.small))
struct GeneratedSourceFileProtectionTests {
    @Test(.issue("https://github.com/swiftlang/swift-package-manager/issues/10288", relationship: .verifies))
    func generatedSwiftSourcesAreReadOnlyBetweenBuilds() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let pluginWorkDirectory = temporaryDirectory.appending("plugins")
            let outputDirectory = pluginWorkDirectory.appending(components: "outputs", "package", "target")
            let generatedSource = outputDirectory.appending("generated.swift")
            let generatedResource = outputDirectory.appending("resource.txt")
            #if !os(Windows)
            let sourceOutsideOutputDirectory = temporaryDirectory.appending("source.swift")
            let generatedSourceSymlink = outputDirectory.appending("source-link.swift")
            #endif
            try localFileSystem.createDirectory(outputDirectory, recursive: true)
            try localFileSystem.writeFileContents(generatedSource, string: "let value = 1")
            try localFileSystem.writeFileContents(generatedResource, string: "resource")
            #if !os(Windows)
            try localFileSystem.writeFileContents(sourceOutsideOutputDirectory, string: "let value = 2")
            try localFileSystem.createSymbolicLink(
                generatedSourceSymlink,
                pointingAt: sourceOutsideOutputDirectory,
                relative: false
            )
            #endif

            let protection = GeneratedSourceFileProtection(
                fileSystem: localFileSystem,
                pluginWorkDirectory: pluginWorkDirectory
            )
            try protection.protectGeneratedSources()

            #expect(!localFileSystem.isWritable(generatedSource))
            #expect(localFileSystem.isWritable(generatedResource))
            #if !os(Windows)
            #expect(localFileSystem.isWritable(sourceOutsideOutputDirectory))
            #endif

            try protection.prepareForBuild()

            #expect(localFileSystem.isWritable(generatedSource))
            #expect(localFileSystem.isWritable(generatedResource))
            #if !os(Windows)
            #expect(localFileSystem.isWritable(sourceOutsideOutputDirectory))
            #endif
        }
    }
}
