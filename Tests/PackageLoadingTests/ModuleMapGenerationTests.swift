/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageModel
@testable import PackageLoading

class ModuleMapGeneration: XCTestCase {

    func testModuleNameHeaderInInclude() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo.h",
            "/Foo.c")

        let expected = BufferedOutputByteStream()
        expected <<< """
            module Foo {
                umbrella header "/include/Foo.h"
                export *
            }

            """

        ModuleMapTester("Foo", in: fs) { result in
            result.check(value: expected.bytes)
        }
    }

    func testModuleNameDirAndHeaderInInclude() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo/Foo.h",
            "/Foo.c")

        let expected = BufferedOutputByteStream()
        expected <<< """
            module Foo {
                umbrella header "/include/Foo/Foo.h"
                export *
            }

            """

        ModuleMapTester("Foo", in: fs) { result in
            result.check(value: expected.bytes)
        }
    }

    func testOtherCases() throws {

        let expected = BufferedOutputByteStream()
        expected <<< """
            module Foo {
                umbrella "/include"
                export *
            }

            """

        var fs: InMemoryFileSystem
        func checkExpected() {
            ModuleMapTester("Foo", in: fs) { result in
                result.check(value: expected.bytes)
            }
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Bar.h",
            "/Foo.c")
        checkExpected()

        // FIXME: Should this be allowed?
        fs = InMemoryFileSystem(emptyFiles:
            "/include/Baz/Foo.h",
            "/include/Bar/Bar.h",
            "/Foo.c")
        checkExpected()

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Baz.h",
            "/include/Bar.h",
            "/Foo.c")
        checkExpected()
    }

    func testWarnings() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.checkNotCreated()
            result.checkDiagnostics("warning: no include directory found for target \'Foo\'; libraries cannot be imported without public headers")
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/F-o-o.h",
            "/Foo.c")
        let expected = BufferedOutputByteStream()
        expected <<< "module F_o_o {\n"
        expected <<< "    umbrella \"/include\"\n"
        expected <<< "    export *\n"
        expected <<< "}\n"
        ModuleMapTester("F-o-o", in: fs) { result in
            result.check(value: expected.bytes)
            result.checkDiagnostics("warning: /include/F-o-o.h should be renamed to /include/F_o_o.h to be used as an umbrella header")
        }
    }

    func testUnsupportedLayouts() throws {
        var fs: InMemoryFileSystem
        func checkExpected(_ str: String, file: StaticString = #file, line: UInt = #line) {
            ModuleMapTester("Foo", in: fs) { result in
                result.checkNotCreated()
                result.checkDiagnostics(str, file: file, line: line)
            }
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo/Foo.h",
            "/include/Bar/Foo.h")
        checkExpected("target 'Foo' failed modulemap generation; umbrella header defined at '/include/Foo/Foo.h', " +
            "but more than one directories exist: /include/Bar, /include/Foo; consider reducing them to one")

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo.h",
            "/include/Bar/Foo.h")
        checkExpected("target 'Foo' failed modulemap generation; umbrella header defined at '/include/Foo.h', but " +
            "directories exist: /include/Bar; consider removing them")
    }

    static var allTests = [
        ("testModuleNameDirAndHeaderInInclude", testModuleNameDirAndHeaderInInclude),
        ("testModuleNameHeaderInInclude", testModuleNameHeaderInInclude),
        ("testOtherCases", testOtherCases),
        ("testUnsupportedLayouts", testUnsupportedLayouts),
        ("testWarnings", testWarnings),
    ]
}

func ModuleMapTester(_ name: String, includeDir: String = "include", in fileSystem: FileSystem, _ body: (ModuleMapResult) -> Void) {
    let includeDir = AbsolutePath.root.appending(component: includeDir)
    let target = ClangTarget(name: name, isCXX: false, languageStandard: nil, includeDir: includeDir, isTest: false, sources: Sources(paths: [], root: .root))
    let warningStream = BufferedOutputByteStream()
    var generator = ModuleMapGenerator(for: target, fileSystem: fileSystem, warningStream: warningStream)
    var diagnostics = Set<String>()
    do {
        try generator.generateModuleMap(inDir: .root)
        // FIXME: Find a better way.
        diagnostics = Set(warningStream.bytes.asReadableString.split(separator: "\n").map(String.init))
    } catch {
      diagnostics.insert("\(error)")
    }
    let genPath = AbsolutePath.root.appending(components: "module.modulemap")
    let result = ModuleMapResult(diagnostics: diagnostics, path: genPath, fs: fileSystem)
    body(result)
    result.validateDiagnostics()
}

final class ModuleMapResult {

    private var diagnostics: Set<String>
    private let path: AbsolutePath
    private let fs: FileSystem

    init(diagnostics: Set<String>, path: AbsolutePath, fs: FileSystem) {
        self.diagnostics = diagnostics
        self.path = path
        self.fs = fs
    }

    func validateDiagnostics(file: StaticString = #file, line: UInt = #line) {
        guard !diagnostics.isEmpty else { return }
        XCTFail("Unchecked diagnostics: \(diagnostics)", file: file, line: line)
    }

    func checkDiagnostics(_ str: String, file: StaticString = #file, line: UInt = #line) {
        if diagnostics.contains(str) {
            diagnostics.remove(str)
        } else {
            XCTFail("no error: \(str) or is already checked", file: file, line: line)
        }
    }

    func checkNotCreated(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(isCreated, false, "unexpected modulemap created: \(contents)", file: file, line: line)
    }

    private var contents: ByteString {
        return try! fs.readFileContents(path)
    }

    private var isCreated: Bool {
        return fs.isFile(path)
    }

    func check(value: ByteString, file: StaticString = #file, line: UInt = #line) {
        guard isCreated else {
            return XCTFail("Can't compare values, modulemap not generated.", file: file, line: line)
        }
        XCTAssertEqual(value, contents, file: file, line: line)
    }
}
