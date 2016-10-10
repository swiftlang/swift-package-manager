/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic

@testable import Utility

final class PkgConfigParserTests: XCTestCase {
    
    func testGTK3PCFile() {
        loadPCFile("gtk+-3.0.pc") { parser in
            guard let parser = parser else { XCTFail("Unexpected parsing error"); return}
            XCTAssertEqual(parser.variables, ["libdir": "/usr/local/Cellar/gtk+3/3.18.9/lib", "gtk_host": "x86_64-apple-darwin15.3.0", "includedir": "/usr/local/Cellar/gtk+3/3.18.9/include", "prefix": "/usr/local/Cellar/gtk+3/3.18.9", "gtk_binary_version": "3.0.0", "exec_prefix": "/usr/local/Cellar/gtk+3/3.18.9", "targets": "quartz"])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk", "cairo", "cairo-gobject", "gdk-pixbuf-2.0", "gio-2.0"])
            XCTAssertEqual(parser.cFlags, ["-I/usr/local/Cellar/gtk+3/3.18.9/include/gtk-3.0"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/Cellar/gtk+3/3.18.9/lib", "-lgtk-3"])
        }
    }
    
    func testEmptyCFlags() {
        loadPCFile("empty_cflags.pc") { parser in
            guard let parser = parser else { XCTFail("Unexpected parsing error"); return}
            XCTAssertEqual(parser.variables, ["prefix": "/usr/local/bin", "exec_prefix": "/usr/local/bin"])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, [])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk-3"])
        }
    }
    
    func testVariableinDependency() {
        loadPCFile("deps_variable.pc") { parser in
            guard let parser = parser else { XCTFail("Unexpected parsing error"); return}
            XCTAssertEqual(parser.variables, ["prefix": "/usr/local/bin", "exec_prefix": "/usr/local/bin", "my_dep": "atk"])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, ["-I"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk-3"])
        }
    }
    
    func testUnresolvablePCFile() {
        loadPCFile("failure_case.pc") { parser in
            if parser != nil {
                XCTFail("parsing should have failed: \(parser.debugDescription)")
            }
        }
    }
    
    func testEscapedSpaces() {
        loadPCFile("escaped_spaces.pc") { parser in
            guard let parser = parser else { XCTFail("Unexpected parsing error"); return}
            XCTAssertEqual(parser.variables, ["prefix": "/usr/local/bin", "exec_prefix": "/usr/local/bin", "my_dep": "atk"])
            XCTAssertEqual(parser.dependencies, ["gdk-3.0", "atk"])
            XCTAssertEqual(parser.cFlags, ["-I/usr/local/Wine Cellar/gtk+3/3.18.9/include/gtk-3.0", "-I/after/extra/spaces"])
            XCTAssertEqual(parser.libs, ["-L/usr/local/bin", "-lgtk-3", "-wantareal\\here", "-one\\", "-two"])
        }
    }
    
    /// Test custom search path get higher priority for locating pc files.
    func testCustomPcFileSearchPath() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/usr/lib/pkgconfig/foo.pc",
            "/custom/foo.pc")
        XCTAssertEqual("/custom/foo.pc", try PkgConfig.locatePCFile(name: "foo", customSearchPaths: [AbsolutePath("/custom")], fileSystem: fs).asString)
        XCTAssertEqual("/usr/lib/pkgconfig/foo.pc", try PkgConfig.locatePCFile(name: "foo", customSearchPaths: [], fileSystem: fs).asString)
    }

    private func loadPCFile(_ inputName: String, body: (PkgConfigParser?) -> Void) {
        let input = AbsolutePath(#file).parentDirectory.appending(components: "pkgconfigInputs", inputName)
        var parser: PkgConfigParser? = PkgConfigParser(pcFile: input, fileSystem: localFileSystem)
        do {
            try parser?.parse()
        } catch {
            parser = nil
        }
        body(parser)
    }

    static var allTests = [
        ("testGTK3PCFile", testGTK3PCFile),
        ("testEmptyCFlags", testEmptyCFlags),
        ("testVariableinDependency", testVariableinDependency),
        ("testUnresolvablePCFile", testUnresolvablePCFile),
        ("testEscapedSpaces", testEscapedSpaces),
        ("testCustomPcFileSearchPath", testCustomPcFileSearchPath),
    ]
}
