//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Testing
import BinarySymbols
import Basics
import PackageModel
import _InternalTestSupport

@Suite
struct ClangHostDefaultObjectsDetectorTests {
    /// `detectDefaultObjects` shells out to the host `clang` (via `-###`) and
    /// parses the default link command, which is only supported on Linux-like
    /// hosts — `swift package audit-binary-artifact` bails out on Darwin and
    /// Windows before calling it. Gate the test the same way so it only runs
    /// where the code path is exercised in practice.
    @Test(
        .enabled(if: !hostTriple.isDarwin() && !hostTriple.isWindows(),
                 "detectDefaultObjects only supports Linux-like hosts and requires a host clang")
    )
    func detectsHostDefaultObjects() async throws {
        let toolchain = try UserToolchain.default
        let clang = try toolchain.getClangCompiler()
        let observability = ObservabilitySystem.makeForTesting()

        let objects = try await detectDefaultObjects(
            clang: clang,
            fileSystem: localFileSystem,
            hostTriple: hostTriple,
            observabilityScope: observability.topScope
        )

        // A functioning host clang always links at least the C runtime, so the
        // detected default object/library set should be non-empty. This also
        // exercises the Subprocess invocation and stderr capture end-to-end.
        #expect(!objects.isEmpty)
        #expect(!observability.hasErrorDiagnostics)
    }
}
