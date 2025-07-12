//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Build
import Commands
import SPMBuildCore

@_spi(SwiftPMInternal)
import DriverSupport

import Foundation
import PackageModel
import SourceControl
import _InternalTestSupport
import Workspace
import Testing

fileprivate func expectThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) throws -> Void = { _ in }
) async rethrows {
    let error = await #expect(throws: SwiftPMError.self, sourceLocation: sourceLocation) {
        try await expression()
    }

    guard case .executionFailure(let processError, let stdout, let stderr) = error,
          case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
          processResult.exitStatus != .terminated(code: 0) else {
        Issue.record("Unexpected error type: \(error?.interpolationDescription)", sourceLocation: sourceLocation)
        return
    }
    try errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
}


extension Trait where Self == Testing.ConditionTrait {
    public static var requiresAPIDigester: Self {
        enabled("This test requires a toolchain with swift-api-digester") {
            (try? UserToolchain.default.getSwiftAPIDigester()) != nil && ProcessInfo.hostOperatingSystem != .windows
        }
    }
}

@Suite
struct APIDiffTests {
    @discardableResult
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: Environment? = nil,
        buildSystem: BuildSystemProvider.Kind
    ) async throws -> (stdout: String, stderr: String) {
        var environment = env ?? [:]
        // don't ignore local packages when caching
        environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
        return try await executeSwiftPackage(
            packagePath,
            extraArgs: args,
            env: environment,
            buildSystem: buildSystem
        )
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testInvokeAPIDiffDigester(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Foo")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(
                packageRoot.appending("Foo.swift"),
                string: "public let foo = 42"
            )
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                #expect(!error.stdout.isEmpty)
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testSimpleAPIDiff(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Foo")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(
                packageRoot.appending("Foo.swift"),
                string: "public let foo = 42"
            )
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                #expect(error.stdout.contains("1 breaking change detected in Foo"))
                #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
            }
        }
    }

    @Test(
        .requiresAPIDigester,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8926", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testMultiTargetAPIDiff(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Baz", "Baz.swift"),
                string: #"public func baz() -> String { "hello, world!" }"#
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Qux", "Qux.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                withKnownIssue {
                    #expect(error.stdout.contains("2 breaking changes detected in Qux"))
                    #expect(error.stdout.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                    #expect(error.stdout.contains("💔 API breakage: var Qux.x has been removed"))
                    #expect(error.stdout.contains("1 breaking change detected in Baz"))
                    #expect(error.stdout.contains("💔 API breakage: func bar() has been removed"))
                } when: {
                    buildSystem == .swiftbuild && ProcessInfo.isHostAmazonLinux2()
                }
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testBreakageAllowlist(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Baz", "Baz.swift"),
                string: #"public func baz() -> String { "hello, world!" }"#
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Qux", "Qux.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            let customAllowlistPath = packageRoot.appending(components: "foo", "allowlist.txt")
            try localFileSystem.writeFileContents(
                customAllowlistPath,
                string: "API breakage: class Qux has generic signature change from <T> to <T, U>\n"
            )
            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3", "--breakage-allowlist-path", customAllowlistPath.pathString],
                            packagePath: packageRoot, buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("1 breaking change detected in Qux"))
                #expect(!error.stdout.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                #expect(error.stdout.contains("💔 API breakage: var Qux.x has been removed"))
                #expect(error.stdout.contains("1 breaking change detected in Baz"))
                #expect(error.stdout.contains("💔 API breakage: func bar() has been removed"))
            }

        }
    }

    @Test(
        .requiresAPIDigester,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8926", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testCheckVendedModulesOnly(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("NonAPILibraryTargets")
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Foo", "Foo.swift"),
                string: #"public func baz() -> String { "hello, world!" }"#
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Bar", "Bar.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Baz", "Baz.swift"),
                string: "public enum Baz {case a, b, c }"
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Qux", "Qux.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                try withKnownIssue {
                    #expect(error.stdout.contains("💔 API breakage"))
                    let regex = try Regex("\\d+ breaking change(s?) detected in Foo")
                    #expect(error.stdout.contains(regex))
                    #expect(error.stdout.contains(regex))
                    #expect(error.stdout.contains(regex))
                } when: {
                    buildSystem == .swiftbuild && ProcessInfo.isHostAmazonLinux2()
                }

                // Qux is not part of a library product, so any API changes should be ignored
                #expect(!error.stdout.contains("Qux"))
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testFilters(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("NonAPILibraryTargets")
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Foo", "Foo.swift"),
                string: #"public func baz() -> String { "hello, world!" }"#
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Bar", "Bar.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Baz", "Baz.swift"),
                string: "public enum Baz {case a, b, c }"
            )
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Qux", "Qux.swift"),
                string: "public class Qux<T, U> { private let x = 1 }"
            )
            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3", "--products", "One", "--targets", "Bar"], packagePath: packageRoot, buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("💔 API breakage"))
                let regex = try Regex("\\d+ breaking change(s?) detected in Foo")
                #expect(error.stdout.contains(regex))
                #expect(error.stdout.contains(regex))

                // Baz and Qux are not included in the filter, so any API changes should be ignored.
                #expect(!error.stdout.contains("Baz"))
                #expect(!error.stdout.contains("Qux"))
            }

            // Diff a target which didn't have a baseline generated as part of the first invocation
            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3", "--targets", "Baz"], packagePath: packageRoot, buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("💔 API breakage"))
                let regex = try Regex("\\d+ breaking change(s?) detected in Baz")
                #expect(error.stdout.contains(regex))

                // Only Baz is included, we should not see any other API changes.
                #expect(!error.stdout.contains("Foo"))
                #expect(!error.stdout.contains("Bar"))
                #expect(!error.stdout.contains("Qux"))
            }

            // Test diagnostics
            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3", "--targets", "NotATarget", "Exec", "--products", "NotAProduct", "Exec"],
                            packagePath: packageRoot, buildSystem: buildSystem)
            ) { error in
                #expect(error.stderr.contains("error: no such product 'NotAProduct'"))
                #expect(error.stderr.contains("error: no such target 'NotATarget'"))
                #expect(error.stderr.contains("'Exec' is not a library product"))
                #expect(error.stderr.contains("'Exec' is not a library target"))
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testAPIDiffOfModuleWithCDependency(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("https://github.com/swiftlang/swift/issues/82394") {
            try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
                let packageRoot = fixturePath.appending("CTargetDep")
                // Overwrite the existing decl.
                try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Bar", "Bar.swift"), string:
                    """
                    import Foo

                    public func bar() -> String {
                        foo()
                        return "hello, world!"
                    }
                    """
                )
                try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                    #expect(error.stdout.contains("1 breaking change detected in Bar"))
                    #expect(error.stdout.contains("💔 API breakage: func bar() has return type change from Swift.Int to Swift.String"))
                }

                // Report an error if we explicitly ask to diff a C-family target
                try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3", "--targets", "Foo"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                    #expect(error.stderr.contains("error: 'Foo' is not a Swift language target"))
                }
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testAPIDiffOfVendoredCDependency(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("https://github.com/swiftlang/swift/issues/82394") {
            try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
                let packageRoot = fixturePath.appending("CIncludePath")
                let (output, _) = try await execute(["diagnose-api-breaking-changes", "main"], packagePath: packageRoot, buildSystem: buildSystem)

                #expect(output.contains("No breaking changes detected in Sample"))
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testNoBreakingChanges(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            // Introduce an API-compatible change
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Baz", "Baz.swift"),
                string: "public func bar() -> Int { 100 }"
            )
            let (output, _) = try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)
            #expect(output.contains("No breaking changes detected in Baz"))
            #expect(output.contains("No breaking changes detected in Qux"))
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testAPIDiffAfterAddingNewTarget(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            try localFileSystem.createDirectory(packageRoot.appending(components: "Sources", "Foo"))
            try localFileSystem.writeFileContents(
                packageRoot.appending(components: "Sources", "Foo", "Foo.swift"),
                string: #"public let foo = "All new module!""#
            )
            try localFileSystem.writeFileContents(packageRoot.appending("Package.swift"), string:
                """
                // swift-tools-version:4.2
                import PackageDescription

                let package = Package(
                    name: "Bar",
                    products: [
                        .library(name: "Baz", targets: ["Baz"]),
                        .library(name: "Qux", targets: ["Qux", "Foo"]),
                    ],
                    targets: [
                        .target(name: "Baz"),
                        .target(name: "Qux"),
                        .target(name: "Foo")
                    ]
                )
                """
            )
            let (output, _) = try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)
            #expect(output.contains("No breaking changes detected in Baz"))
            #expect(output.contains("No breaking changes detected in Qux"))
            #expect(output.contains("Skipping Foo because it does not exist in the baseline"))
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testAPIDiffPackageWithPlugin(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("WithPlugin")
            let (output, _) = try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)
            #expect(output.contains("No breaking changes detected in TargetLib"))
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testBadTreeish(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Foo")
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "7.8.9"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                #expect(error.stderr.contains("error: Couldn’t get revision"))
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testBranchUpdate(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withTemporaryDirectory { baselineDir in
            try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
                let packageRoot = fixturePath.appending("Foo")
                let repo = GitRepository(path: packageRoot)
                try repo.checkout(newBranch: "feature")
                // Overwrite the existing decl.
                try localFileSystem.writeFileContents(
                    packageRoot.appending("Foo.swift"),
                    string: "public let foo = 42"
                )
                try repo.stage(file: "Foo.swift")
                try repo.commit(message: "Add foo")
                try await expectThrowsCommandExecutionError(
                    try await execute(["diagnose-api-breaking-changes", "main", "--baseline-dir", baselineDir.pathString],
                                      packagePath: packageRoot,
                                      buildSystem: buildSystem)
                ) { error in
                    #expect(error.stdout.contains("1 breaking change detected in Foo"))
                    #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
                }

                // Update `main` and ensure the baseline is regenerated.
                try repo.checkout(revision: .init(identifier: "main"))
                try localFileSystem.writeFileContents(
                    packageRoot.appending("Foo.swift"),
                    string: "public let foo = 42"
                )
                try repo.stage(file: "Foo.swift")
                try repo.commit(message: "Add foo")
                try repo.checkout(revision: .init(identifier: "feature"))
                let (output, _) = try await execute(["diagnose-api-breaking-changes", "main", "--baseline-dir", baselineDir.pathString],
                                                    packagePath: packageRoot,
                                                    buildSystem: buildSystem)
                #expect(output.contains("No breaking changes detected in Foo"))
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testBaselineDirOverride(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Foo")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(
                packageRoot.appending("Foo.swift"),
                string: "public let foo = 42"
            )

            let baselineDir = fixturePath.appending("Baselines")
            let repo = GitRepository(path: packageRoot)
            let revision = try repo.resolveRevision(identifier: "1.2.3")

            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3", "--baseline-dir", baselineDir.pathString], packagePath: packageRoot, buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("1 breaking change detected in Foo"))
                #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
                let baseName: String
                if buildSystem == .swiftbuild {
                    baseName = "Foo"
                } else {
                    baseName = "Foo.json"
                }
                #expect(localFileSystem.exists(baselineDir.appending(components: revision.identifier, baseName)))
            }
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testRegenerateBaseline(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("Foo")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(
                packageRoot.appending("Foo.swift"),
                string: "public let foo = 42"
            )

            let repo = GitRepository(path: packageRoot)
            let revision = try repo.resolveRevision(identifier: "1.2.3")

            let baselineDir = fixturePath.appending("Baselines")
            let fooBaselinePath: AbsolutePath
            if buildSystem == .swiftbuild {
                fooBaselinePath = baselineDir.appending(components: revision.identifier, "Foo")
            } else {
                fooBaselinePath = baselineDir.appending(components: revision.identifier, "Foo.json")
            }

            var initialTimestamp: Date?
            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3",
                             "--baseline-dir", baselineDir.pathString],
                            packagePath: packageRoot,
                                 buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("1 breaking change detected in Foo"))
                #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
                #expect(localFileSystem.exists(fooBaselinePath))
                initialTimestamp = try localFileSystem.getFileInfo(fooBaselinePath).modTime
            }

            // Accomodate filesystems with low resolution timestamps
            try await Task.sleep(for: .seconds(1))

            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3",
                             "--baseline-dir", baselineDir.pathString],
                            packagePath: packageRoot,
                                 buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("1 breaking change detected in Foo"))
                #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
                let newTimestamp = try localFileSystem.getFileInfo(fooBaselinePath).modTime
                #expect(newTimestamp == initialTimestamp)
            }

            // Accomodate filesystems with low resolution timestamps
            try await Task.sleep(for: .seconds(1))

            try await expectThrowsCommandExecutionError(
                try await execute(["diagnose-api-breaking-changes", "1.2.3",
                             "--baseline-dir", baselineDir.pathString, "--regenerate-baseline"],
                            packagePath: packageRoot,
                                 buildSystem: buildSystem)
            ) { error in
                #expect(error.stdout.contains("1 breaking change detected in Foo"))
                #expect(error.stdout.contains("💔 API breakage: func foo() has been removed"))
                #expect((try? localFileSystem.getFileInfo(fooBaselinePath).modTime) != initialTimestamp)
            }
        }
    }

    @Test(arguments: SupportedBuildSystemOnAllPlatforms)
    func testOldName(buildSystem: BuildSystemProvider.Kind) async throws {
        try await expectThrowsCommandExecutionError(try await execute(["experimental-api-diff", "1.2.3", "--regenerate-baseline"], packagePath: nil, buildSystem: buildSystem)) { error in
            #expect(error.stdout.contains("`swift package experimental-api-diff` has been renamed to `swift package diagnose-api-breaking-changes`"))
        }
    }

    @Test(.requiresAPIDigester, arguments: SupportedBuildSystemOnAllPlatforms)
    func testBrokenAPIDiff(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/APIDiff/") { fixturePath in
            let packageRoot = fixturePath.appending("BrokenPkg")
            try await expectThrowsCommandExecutionError(try await execute(["diagnose-api-breaking-changes", "1.2.3"], packagePath: packageRoot, buildSystem: buildSystem)) { error in
                let expectedError: String
                if buildSystem == .swiftbuild {
                    expectedError = "error: Build failed"
                } else {
                    expectedError = "baseline for Swift2 contains no symbols, swift-api-digester output"
                }
                #expect(error.stderr.contains(expectedError))
            }
        }
    }
}
