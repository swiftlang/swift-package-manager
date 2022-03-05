/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

class ModuleMapGeneration: XCTestCase {

    func testModuleNameHeaderInInclude() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo.h",
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.check(contents: """
            module Foo {
                umbrella header "/include/Foo.h"
                export *
            }

            """)
        }
    }

    func testModuleNameDirAndHeaderInInclude() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo/Foo.h",
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.check(contents: """
            module Foo {
                umbrella header "/include/Foo/Foo.h"
                export *
            }

            """)
        }
    }

    func testOtherCases() throws {
        var fs: InMemoryFileSystem

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Bar.h",
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.check(contents: """
            module Foo {
                umbrella "/include"
                export *
            }

            """)
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Baz.h",
            "/include/Bar.h",
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.check(contents: """
            module Foo {
                umbrella "/include"
                export *
            }

            """)
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Baz/Foo.h",
            "/include/Bar/Bar.h",
            "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.check(contents: """
            module Foo {
                umbrella "/include"
                export *
            }

            """)
        }
    }

    func testWarnings() throws {
        var fs = InMemoryFileSystem(emptyFiles: "/Foo.c")
        ModuleMapTester("Foo", in: fs) { result in
            result.checkNotCreated()
            result.checkDiagnostics { result in
                let diagnostic = result.check(
                    diagnostic: "no include directory found for target \'Foo\'; libraries cannot be imported without public headers",
                    severity: .warning
                )
                XCTAssertEqual(diagnostic?.metadata?.targetName, "Foo")
            }
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/F-o-o.h",
            "/Foo.c")
        ModuleMapTester("F-o-o", in: fs) { result in
            result.check(contents: """
                module F_o_o {
                    umbrella "/include"
                    export *
                }

                """)
            result.checkDiagnostics { result in
                let diagnostic = result.check(
                    diagnostic: "/include/F-o-o.h should be renamed to /include/F_o_o.h to be used as an umbrella header",
                    severity: .warning
                )
                XCTAssertEqual(diagnostic?.metadata?.targetName, "F-o-o")
            }
        }
    }

    func testUnsupportedLayouts() throws {
        var fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo/Foo.h",
            "/include/Bar/Foo.h")
        ModuleMapTester("Foo", in: fs) { result in
            result.checkNotCreated()
            result.checkDiagnostics { result in
                let diagnostic = result.check(
                    diagnostic: "target 'Foo' has invalid header layout: umbrella header found at '/include/Foo/Foo.h', but more than one directory exists next to its parent directory: /include/Bar; consider reducing them to one",
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.targetName, "Foo")
            }
        }

        fs = InMemoryFileSystem(emptyFiles:
            "/include/Foo.h",
            "/include/Bar/Foo.h")
        ModuleMapTester("Foo", in: fs) { result in
            result.checkNotCreated()
            result.checkDiagnostics { result in
                let diagnostic = result.check(
                    diagnostic: "target 'Foo' has invalid header layout: umbrella header found at '/include/Foo.h', but directories exist next to it: /include/Bar; consider removing them",
                    severity: .error
                )
                XCTAssertEqual(diagnostic?.metadata?.targetName, "Foo")
            }
        }
    }
}

/// Helper function to test module map generation.  Given a target name and optionally the name of a public-headers directory, this function determines the module map type of the public-headers directory by examining the contents of a file system and invokes a given block to check the module result (including any diagnostics).
func ModuleMapTester(_ targetName: String, includeDir: String = "include", in fileSystem: FileSystem, _ body: (ModuleMapResult) -> Void) {
    let observability = ObservabilitySystem.makeForTesting()
    // Create a module map generator, and determine the type of module map to use for the header directory.  This may emit diagnostics.
    let moduleMapGenerator = ModuleMapGenerator(targetName: targetName, moduleName: targetName.spm_mangledToC99ExtendedIdentifier(), publicHeadersDir: AbsolutePath.root.appending(component: includeDir), fileSystem: fileSystem)
    let moduleMapType = moduleMapGenerator.determineModuleMapType(observabilityScope: observability.topScope)
    
    // Generate a module map and capture any emitted diagnostics.
    let generatedModuleMapPath = AbsolutePath.root.appending(components: "module.modulemap")
    observability.topScope.trap {
        if let generatedModuleMapType = moduleMapType.generatedModuleMapType {
            try moduleMapGenerator.generateModuleMap(type: generatedModuleMapType, at: generatedModuleMapPath)
        }
    }
    
    // Invoke the closure to check the results.
    let result = ModuleMapResult(diagnostics: observability.diagnostics, path: generatedModuleMapPath, fs: fileSystem)
    body(result)
    
    // Check for any unexpected diagnostics (the ones the closure didn't check for).
    result.validateDiagnostics()
}

final class ModuleMapResult {
    private var diagnostics: [Basics.Diagnostic]
    private var diagsChecked: Bool
    private let path: AbsolutePath
    private let fs: FileSystem

    init(diagnostics: [Basics.Diagnostic], path: AbsolutePath, fs: FileSystem) {
        self.diagnostics = diagnostics
        self.diagsChecked = false
        self.path = path
        self.fs = fs
    }

    func validateDiagnostics(file: StaticString = #file, line: UInt = #line) {
        if diagsChecked || diagnostics.isEmpty { return }
        XCTFail("Unchecked diagnostics: \(diagnostics)", file: (file), line: line)
    }

    func checkDiagnostics(_ handler: (DiagnosticsTestResult) throws -> Void) {
        testDiagnostics(diagnostics, handler: handler)
        diagsChecked = true
    }

    func checkNotCreated(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(isCreated, false, "unexpected modulemap created: \(contents)", file: (file), line: line)
    }

    private var contents: String {
        return try! fs.readFileContents(path)
    }

    private var isCreated: Bool {
        return fs.isFile(path)
    }

    func check(contents: String, file: StaticString = #file, line: UInt = #line) {
        guard isCreated else {
            return XCTFail("Can't compare values, modulemap not generated.", file: (file), line: line)
        }
        XCTAssertEqual(contents, self.contents, file: (file), line: line)
    }
}
