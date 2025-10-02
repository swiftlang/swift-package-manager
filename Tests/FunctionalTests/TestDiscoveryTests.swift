//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SPMBuildCore
import _InternalTestSupport
import Testing
import struct Foundation.UUID
import class Foundation.ProcessInfo

@Suite
struct TestDiscoveryTests {
    static var buildSystems: [BuildSystemProvider.Kind] = [BuildSystemProvider.Kind.native, .swiftbuild]

    @Test(arguments: buildSystems)
    func build(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (stdout, _) = try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
                // in "swift build" build output goes to stdout
                #expect(stdout.contains("Build complete!"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(arguments: buildSystems)
    func discovery(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, extraArgs: ["-vv"], buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("Executed 3 tests"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(.bug("https://github.com/swiftlang/swift-build/issues/13"), arguments: [BuildSystemProvider.Kind.native])
    func nonStandardName(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/hello world") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
            // in "swift test" build output goes to stderr
            #expect(stderr.contains("Build complete!"))
            // in "swift test" test output goes to stdout
            #expect(stdout.contains("Executed 1 test"))
        }
    }

    @Test(arguments: buildSystems)
    func asyncMethods(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Async") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("Executed 4 tests"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    // FIXME: eliminate extraneous warnings with --build-system swiftbuild
    @Test(.bug("https://github.com/swiftlang/swift-build/issues/573"), .skipHostOS(.macOS), arguments: [BuildSystemProvider.Kind.native])
    func discovery_whenNoTests(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/NoTests") { fixturePath in
            let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
            // in "swift test" build output goes to stderr
            #expect(stderr.contains("Build complete!"))
            // we are expecting that no warning is produced
            #expect(!stderr.contains("warning:"))
            // in "swift test" test output goes to stdout
            #expect(stdout.contains("Executed 0 tests"))
        }
    }

    // FIXME: --build-system swiftbuild should support hand-authored entry points.
    @Test(.bug("https://github.com/swiftlang/swift-build/issues/572"), .skipHostOS(.macOS), arguments: [BuildSystemProvider.Kind.native])
    func entryPointOverride(_ buildSystem: BuildSystemProvider.Kind) async throws {
        for name in SwiftModule.testEntryPointNames {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let random = UUID().uuidString
                let manifestPath = fixturePath.appending(components: "Tests", name)
                try localFileSystem.writeFileContents(manifestPath, string: "print(\"\(random)\")")
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(!stdout.contains("Executed 1 test"))
                #expect(stdout.contains(random))
            }
        }
    }

    @Test(.skipHostOS(.macOS), arguments: buildSystems)
    func entryPointOverrideIgnored(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let manifestPath = fixturePath.appending(components: "Tests", SwiftModule.defaultTestEntryPointName)
                try localFileSystem.writeFileContents(manifestPath, string: "fatalError(\"should not be called\")")
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, extraArgs: ["--enable-test-discovery"], buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(!stdout.contains("Executed 1 test"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(.skipHostOS(.macOS), arguments: buildSystems)
    func testExtensions(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Extensions") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("SimpleTests1.testExample1"))
                #expect(stdout.contains("SimpleTests1.testExample1_a"))
                #expect(stdout.contains("SimpleTests2.testExample2"))
                #expect(stdout.contains("SimpleTests2.testExample2_a"))
                #expect(stdout.contains("SimpleTests4.testExample"))
                #expect(stdout.contains("SimpleTests4.testExample1"))
                #expect(stdout.contains("SimpleTests4.testExample2"))
                #expect(stdout.contains("Executed 7 tests"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(.skipHostOS(.macOS), arguments: buildSystems)
    func deprecatedTests(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Deprecation") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("Executed 2 tests"))
                #expect(!stderr.contains("is deprecated"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(.skipHostOS(.macOS), arguments: buildSystems)
    func testSubclassedTestClassTests(_ buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("Windows builds encounter long path handling issues", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Subclass") { fixturePath in
                let (stdout, stderr) = try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
                // in "swift test" build output goes to stderr
                #expect(stderr.contains("Build complete!"))
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("Tests3.test11"))
                #expect(stdout.contains("->Module1::Tests1::test11"))
                #expect(stdout.contains("Tests3.test12"))
                #expect(stdout.contains("->Module1::Tests1::test12"))
                #expect(stdout.contains("Tests3.test13"))
                #expect(stdout.contains("->Module1::Tests1::test13"))
                #expect(stdout.contains("Tests3.test21"))
                #expect(stdout.contains("->Module1::Tests2::test21"))
                #expect(stdout.contains("Tests3.test22"))
                #expect(stdout.contains("->Module1::Tests2::test22"))
                #expect(stdout.contains("Tests3.test31"))
                #expect(stdout.contains("->Module1::Tests3::test31"))
                #expect(stdout.contains("Tests3.test32"))
                #expect(stdout.contains("->Module1::Tests3::test32"))
                #expect(stdout.contains("Tests3.test33"))
                #expect(stdout.contains("->Module1::Tests3::test33"))

                #expect(stdout.contains("->Module2::Tests1::test11"))
                #expect(stdout.contains("->Module2::Tests1::test12"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }
}
