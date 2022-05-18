//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageLoading
import TSCBasic
import SPMTestSupport
import XCTest

final class PkgConfigParserTests: XCTestCase {
    func testCircularPCFile() throws {
        let observability = ObservabilitySystem.makeForTesting()

        _ = try PkgConfig(
            name: "harfbuzz",
            additionalSearchPaths: [AbsolutePath(#file).parentDirectory.appending(components: "pkgconfigInputs")],
            fileSystem: localFileSystem,
            observabilityScope: observability.topScope
        )

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .equal("circular dependency detected while parsing harfbuzz: harfbuzz -> freetype2 -> harfbuzz"), severity: .warning)
        }
    }

    func testGTK3PCFile() {
        try! loadPCFile("gtk+-3.0.pc") { parser in
            XCTAssertEqual(parser.variables, [
                "libdir": "/usr/local/Cellar/gtk+3/3.18.9/lib",
                "gtk_host": "x86_64-apple-darwin15.3.0",
                "includedir": "/usr/local/Cellar/gtk+3/3.18.9/include",
                "prefix": "/usr/local/Cellar/gtk+3/3.18.9",
                "gtk_binary_version": "3.0.0",
                "exec_prefix": "/usr/local/Cellar/gtk+3/3.18.9",
                "targets": "quartz",
                "pcfiledir": parser.pcFile.parentDirectory.pathString,
                "pc_sysrootdir": AbsolutePath.root.pathString
            ])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk", "cairo", "cairo-gobject", "gdk-pixbuf-2.0", "gio-2.0"])
            XCTAssertEqual(parser.privateDependencies, ["atk", "epoxy", "gio-unix-2.0"])
            XCTAssertEqual(parser.cFlags, ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3"])
        }
    }

    func testEmptyCFlags() {
        try! loadPCFile("empty_cflags.pc") { parser in
            XCTAssertEqual(parser.variables, [
                "prefix": "/usr/local/bin",
                "exec_prefix": "/usr/local/bin",
                "pcfiledir": parser.pcFile.parentDirectory.pathString,
                "pc_sysrootdir": AbsolutePath.root.pathString
            ])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, [])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk-3"])
        }
    }

    func testVariableinDependency() {
        try! loadPCFile("deps_variable.pc") { parser in
            XCTAssertEqual(parser.variables, [
                "prefix": "/usr/local/bin",
                "exec_prefix": "/usr/local/bin",
                "my_dep": "atk",
                "pcfiledir": parser.pcFile.parentDirectory.pathString,
                "pc_sysrootdir": AbsolutePath.root.pathString
            ])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, ["-I"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk-3"])
        }
    }

    func testUnresolvablePCFile() throws {
        do {
            try loadPCFile("failure_case.pc")
            XCTFail("Unexpected success")
        } catch PkgConfigError.parsingError(let desc) {
            XCTAssert(desc.hasPrefix("Expected a value for variable"))
        }
    }

    func testEscapedSpaces() {
        try! loadPCFile("escaped_spaces.pc") { parser in
            XCTAssertEqual(parser.variables, [
                "prefix": "/usr/local/bin",
                "exec_prefix": "/usr/local/bin",
                "my_dep": "atk",
                "pcfiledir": parser.pcFile.parentDirectory.pathString,
                "pc_sysrootdir": AbsolutePath.root.pathString
            ])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, ["-I/usr/local/Wine Cellar/gtk+3/3.18.9/include/gtk-3.0", "-I/after/extra/spaces"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk 3", "-wantareal\\here", "-one\\", "-two"])
        }
    }

    /// Test custom search path get higher priority for locating pc files.
    func testCustomPcFileSearchPath() throws {
        let observability = ObservabilitySystem.makeForTesting()

        /// Temporary workaround for PCFileFinder's use of static variables.
        PCFileFinder.resetCachedPkgConfigPaths()

        let fs = InMemoryFileSystem(emptyFiles:
            "/usr/lib/pkgconfig/foo.pc",
            "/usr/local/opt/foo/lib/pkgconfig/foo.pc",
            "/custom/foo.pc")
        XCTAssertEqual(
            AbsolutePath("/custom/foo.pc"),
            try PCFileFinder().locatePCFile(name: "foo", customSearchPaths: [AbsolutePath("/custom")], fileSystem: fs, observabilityScope: observability.topScope)
        )
        XCTAssertEqual(
            AbsolutePath("/custom/foo.pc"),
            try PkgConfig(name: "foo", additionalSearchPaths: [AbsolutePath("/custom")], fileSystem: fs, observabilityScope: observability.topScope).pcFile
        )
        XCTAssertEqual(
            AbsolutePath("/usr/lib/pkgconfig/foo.pc"),
            try PCFileFinder().locatePCFile(name: "foo", customSearchPaths: [], fileSystem: fs, observabilityScope: observability.topScope)
        )
        try withCustomEnv(["PKG_CONFIG_PATH": "/usr/local/opt/foo/lib/pkgconfig"]) {
            XCTAssertEqual(AbsolutePath("/usr/local/opt/foo/lib/pkgconfig/foo.pc"), try PkgConfig(name: "foo", fileSystem: fs, observabilityScope: observability.topScope).pcFile)
        }
#if os(Windows)
        let separator = ";"
#else
        let separator = ":"
#endif
        try withCustomEnv(["PKG_CONFIG_PATH": "/usr/local/opt/foo/lib/pkgconfig\(separator)/usr/lib/pkgconfig"]) {
            XCTAssertEqual(AbsolutePath("/usr/local/opt/foo/lib/pkgconfig/foo.pc"), try PkgConfig(name: "foo", fileSystem: fs, observabilityScope: observability.topScope).pcFile)
        }
    }

    func testBrewPrefix() throws {
        /// Temporary workaround for PCFileFinder's use of static variables.
        PCFileFinder.resetCachedPkgConfigPaths()

        try testWithTemporaryDirectory { tmpdir in
#if os(Windows)
            let fakePkgConfig = tmpdir.appending(components: "bin", "pkg-config.cmd")
#else
            let fakePkgConfig = tmpdir.appending(components: "bin", "pkg-config")
#endif
            try localFileSystem.createDirectory(fakePkgConfig.parentDirectory)

            let stream = BufferedOutputByteStream()
#if os(Windows)
            stream <<< """
            @echo off
            echo /Volumes/BestDrive/pkgconfig
            """
#else
            stream <<< """
            #!/bin/sh
            echo "/Volumes/BestDrive/pkgconfig"
            """
#endif
            try localFileSystem.writeFileContents(fakePkgConfig, bytes: stream.bytes)
            try localFileSystem.chmod(.executable, path: fakePkgConfig, options: [])

#if os(Windows)
            _ = PCFileFinder(pkgConfig: fakePkgConfig)
#else
            _ = PCFileFinder(brewPrefix: fakePkgConfig.parentDirectory.parentDirectory)
#endif
        }

        XCTAssertEqual(PCFileFinder.pkgConfigPaths, [AbsolutePath("/Volumes/BestDrive/pkgconfig")])
    }

    func testAbsolutePathDependency() throws {

        let libffiPath = "/usr/local/opt/libffi/lib/pkgconfig/libffi.pc"

        try loadPCFile("gobject-2.0.pc") { parser in
            XCTAssert(parser.dependencies.isEmpty)
            XCTAssertEqual(parser.privateDependencies, [libffiPath])
        }

        try loadPCFile("libffi.pc") { parser in
            XCTAssert(parser.dependencies.isEmpty)
            XCTAssert(parser.privateDependencies.isEmpty)
        }

        let fileSystem = try InMemoryFileSystem(
            files: [
                "/usr/local/opt/glib/lib/pkgconfig/gobject-2.0.pc": pcFileByteString("gobject-2.0.pc"),
                libffiPath: pcFileByteString("libffi.pc")
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()

        XCTAssertNoThrow(
            try PkgConfig(
                name: "gobject-2.0",
                additionalSearchPaths: [AbsolutePath("/usr/local/opt/glib/lib/pkgconfig")],
                brewPrefix: AbsolutePath("/usr/local"),
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
        )
    }

    func testUnevenQuotes() throws {
        do {
            try loadPCFile("quotes_failure.pc")
            XCTFail("Unexpected success")
        } catch PkgConfigError.parsingError(let desc) {
            XCTAssert(desc.hasPrefix("Text ended before matching quote"))
        }
    }

    private func pcFilePath(_ inputName: String) -> AbsolutePath {
        return AbsolutePath(#file).parentDirectory.appending(components: "pkgconfigInputs", inputName)
    }

    private func loadPCFile(_ inputName: String, body: ((PkgConfigParser) -> Void)? = nil) throws {
        var parser = try PkgConfigParser(pcFile: pcFilePath(inputName), fileSystem: localFileSystem)
        try parser.parse()
        body?(parser)
    }

    private func pcFileByteString(_ inputName: String) throws -> ByteString {
        return try localFileSystem.readFileContents(pcFilePath(inputName))
    }
}
