//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import Testing
import _InternalTestSupport

/// Verifies that PIF generation is deterministic across every fixture in the repo.
@Suite(
    .serialized,
    .tags(.TestSize.large),
    .disabled("Disabled by default because these are very expensive to run")
)
struct PIFDeterminismTests {
    static let regenerationCount = 5

    static let fixturePackages: [String] = {
        let fixturesDir = AbsolutePath("../../../Fixtures", relativeTo: #filePath)
        var roots: [String] = []

        func walk(_ dir: AbsolutePath) {
            guard let contents = try? localFileSystem.getDirectoryContents(dir).sorted() else {
                return
            }

            if contents.contains("Package.swift") {
                roots.append(dir.relative(to: fixturesDir).pathString)
                return
            }

            for entry in contents {
                let child = dir.appending(component: entry)
                if localFileSystem.isDirectory(child), !localFileSystem.isSymlink(child) {
                    walk(child)
                }
            }
        }

        walk(fixturesDir)
        // This fixture has unicode in the path which crashes the Swift Testing harness
        return roots.filter { !$0.hasPrefix("Miscellaneous/UnicodeDependency") }
    }()

    @Test(arguments: fixturePackages)
    func pifGenerationIsDeterministic(fixtureName: String) async throws {
        try await fixture(name: fixtureName) { fixturePath in
            var dumps: [String] = []

            for run in 0 ..< Self.regenerationCount {
                let result: (stdout: String, stderr: String)
                do {
                    result = try await executeSwiftPackage(
                        fixturePath,
                        extraArgs: ["--manifest-cache", "local", "dump-pif"],
                        buildSystem: .swiftbuild,
                    )
                } catch {
                    if run == 0 {
                        // Skip fixtures which are intentionally broken packages.
                        return
                    }
                    throw error
                }
                dumps.append(result.stdout)
            }

            for (index, dump) in dumps.enumerated().dropFirst() where dump != dumps[0] {
                let firstDifference = zip(
                    dumps[0].split(separator: "\n", omittingEmptySubsequences: false),
                    dump.split(separator: "\n", omittingEmptySubsequences: false)
                ).first { $0 != $1 }

                Issue.record("""
                    PIF for fixture '\(fixtureName)' is not deterministic: run \(index + 1) of \
                    \(Self.regenerationCount) differs from run 1.
                    First differing line:
                      run 1: \(firstDifference?.0 ?? "<none>")
                      run \(index + 1): \(firstDifference?.1 ?? "<none>")
                    """)
                break
            }
        }
    }
}
