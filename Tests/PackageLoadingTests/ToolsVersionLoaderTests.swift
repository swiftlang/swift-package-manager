/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import SPMTestSupport

import PackageModel
import PackageLoading
import TSCUtility

class ToolsVersionLoaderTests: XCTestCase {

    let loader = ToolsVersionLoader()

    func load(_ bytes: ByteString, _ body: ((ToolsVersion) -> Void)? = nil) throws {
        let fs = InMemoryFileSystem()
        let path = AbsolutePath("/pkg/Package.swift")
        try! fs.createDirectory(path.parentDirectory, recursive: true)
        try! fs.writeFileContents(path, bytes: bytes)
        let toolsVersion = try loader.load(at: AbsolutePath("/pkg"), fileSystem: fs)
        body?(toolsVersion)
    }

    func testValidVersions() throws {

        let validVersions = [
            // No spacing between "//" and "swift-tools-version" for Swift > 5.3:
            "//swift-tools-version:5.4"                : (5, 4, 0, "5.4.0"),
            "//swift-tools-version:5.4-dev"            : (5, 4, 0, "5.4.0"),
            "//swift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "//swift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "//swift-tools-version:6.1.2"              : (6, 1, 2, "6.1.2"),
            "//swift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "//swift-tools-vErsion:6.1.2;;;;;"         : (6, 1, 2, "6.1.2"),
            "//swift-tools-version:6.1.2;x;x;x;x;x;"   : (6, 1, 2, "6.1.2"),
            "//swift-toolS-version:5.5.2;hello"        : (5, 5, 2, "5.5.2"),
            "//sWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n"       : (5, 5, 2, "5.5.2"),
            // 1 space (U+0020) between "//" and "swift-tools-version":
            "// swift-tools-version:3.1"                : (3, 1, 0, "3.1.0"),
            "// swift-tools-version:3.1-dev"            : (3, 1, 0, "3.1.0"),
            "// swift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "// swift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "// swift-tools-version:3.1.2"              : (3, 1, 2, "3.1.2"),
            "// swift-tools-version:3.1.2;"             : (3, 1, 2, "3.1.2"),
            "// swift-tools-vErsion:3.1.2;;;;;"         : (3, 1, 2, "3.1.2"),
            "// swift-tools-version:3.1.2;x;x;x;x;x;"   : (3, 1, 2, "3.1.2"),
            "// swift-toolS-version:3.5.2;hello"        : (3, 5, 2, "3.5.2"),
            "// sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : (3, 5, 2, "3.5.2"),
            // 1 character tabulation (U+0009) between "//" and "swift-tools-version" for Swift > 5.3:
            "//\tswift-tools-version:5.4"                : (5, 4, 0, "5.4.0"),
            "//\tswift-tools-version:5.4-dev"            : (5, 4, 0, "5.4.0"),
            "//\tswift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "//\tswift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "//\tswift-tools-version:6.1.2"              : (6, 1, 2, "6.1.2"),
            "//\tswift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "//\tswift-tools-vErsion:6.1.2;;;;;"         : (6, 1, 2, "6.1.2"),
            "//\tswift-tools-version:6.1.2;x;x;x;x;x;"   : (6, 1, 2, "6.1.2"),
            "//\tswift-toolS-version:5.5.2;hello"        : (5, 5, 2, "5.5.2"),
            "//\tsWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n"       : (5, 5, 2, "5.5.2"),
            // 1 character tabulation (U+0009) followed by 1 space (U+0020) between "//" and "swift-tools-version" for Swift > 5.3:
            "// \tswift-tools-version:5.4"                : (5, 4, 0, "5.4.0"),
            "// \tswift-tools-version:5.4-dev"            : (5, 4, 0, "5.4.0"),
            "// \tswift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "// \tswift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "// \tswift-tools-version:6.1.2"              : (6, 1, 2, "6.1.2"),
            "// \tswift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "// \tswift-tools-vErsion:6.1.2;;;;;"         : (6, 1, 2, "6.1.2"),
            "// \tswift-tools-version:6.1.2;x;x;x;x;x;"   : (6, 1, 2, "6.1.2"),
            "// \tswift-toolS-version:5.5.2;hello"        : (5, 5, 2, "5.5.2"),
            "// \tsWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n"       : (5, 5, 2, "5.5.2"),
            // An assortment of horizontal whitespace characters between "//" and "swift-tools-version" for Swift > 5.3:
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.4"                : (5, 4, 0, "5.4.0"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.4-dev"            : (5, 4, 0, "5.4.0"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.8.0"              : (5, 8, 0, "5.8.0"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.8.0-dev.al+sha.x" : (5, 8, 0, "5.8.0"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2"              : (6, 1, 2, "6.1.2"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-vErsion:6.1.2;;;;;"         : (6, 1, 2, "6.1.2"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2;x;x;x;x;x;"   : (6, 1, 2, "6.1.2"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-toolS-version:5.5.2;hello"        : (5, 5, 2, "5.5.2"),
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}sWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n"       : (5, 5, 2, "5.5.2"),
        ]

        for (version, result) in validVersions {
            try load(ByteString(encodingAsUTF8: version)) { toolsVersion in
                XCTAssertEqual(toolsVersion.major, result.0)
                XCTAssertEqual(toolsVersion.minor, result.1)
                XCTAssertEqual(toolsVersion.patch, result.2)
                XCTAssertEqual(toolsVersion.description, result.3)
            }
        }


        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// swift-tools-version:3.1.0\n\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion.description, "3.1.0")
            }
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// swift-tools-version:3.1.0\n"
            stream <<< "// swift-tools-version:4.1.0\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion.description, "3.1.0")
            }
        }
    }

    func testNonMatching() throws {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< "// \n"
            stream <<< "// swift-tools-version:6.1.0\n"
            stream <<< "// swift-tools-version:4.1.0\n\n\n\n"
            stream <<< "let package = .."
            try load(stream.bytes) { toolsVersion in
                XCTAssertEqual(toolsVersion, .v3)
            }
        }

        try load("// \n// swift-tools-version:6.1.0\n") { toolsVersion in
            XCTAssertEqual(toolsVersion, .v3)
        }

        assertFailure("//swift-tools-:6.1.0\n", "//swift-tools-:6.1.0")
        assertFailure("//swift-tool-version:6.1.0\n", "//swift-tool-version:6.1.0")
        assertFailure("//  swift-tool-version:6.1.0\n", "//  swift-tool-version:6.1.0")
        assertFailure("// swift-tool-version:6.1.0\n", "// swift-tool-version:6.1.0")
        assertFailure("noway// swift-tools-version:6.1.0\n", "noway// swift-tools-version:6.1.0")
        assertFailure("// swift-tool-version:2.1.0\n// swift-tools-version:6.1.0\n", "// swift-tool-version:2.1.0")

        assertFailure("// haha swift-tools-version:6.1.0\n", "// haha swift-tools-version:6.1.0")
        assertFailure("//// swift-tools-version:6.1.0\n", "//// swift-tools-version:6.1.0")
        assertFailure("// swift-tools-version 6.1.0\n", "// swift-tools-version 6.1.0")
        assertFailure("// swift-tOols-Version 6.1.0\n", "// swift-tOols-Version 6.1.0")
        assertFailure("// swift-tools-version:6.1.2.0\n", "6.1.2.0")
        assertFailure("// swift-tools-version:-1.1.2\n", "-1.1.2")
        assertFailure("// swift-tools-version:3.1hello", "3.1hello")
        
        // Verify no matching for vertical whitespace characters between "//" and "swift-tools-version":
        // Newline is excluded from these assertions, because `ToolsVersionLoader` assumes the default Swift version to be 3.1, if it sees a newline character before finding 1 of the 2 pre-defined misspellings in the specification.
        assertFailure("//\rswift-tools-version:5.3\n", "//\rswift-tools-version:5.3")
        assertFailure("// \rswift-tools-version:5.3\n", "// \rswift-tools-version:5.3")
        assertFailure("//\r swift-tools-version:5.3\n", "//\r swift-tools-version:5.3")
        assertFailure("//\u{B}swift-tools-version:5.3\n", "//\u{B}swift-tools-version:5.3")
        assertFailure("//\u{2028}swift-tools-version:5.3\n", "//\u{2028}swift-tools-version:5.3")
        assertFailure("//\u{2029}swift-tools-version:5.3\n", "//\u{2029}swift-tools-version:5.3")
        
        // Verify no matching for related Unicode characters without `White_Space` property, between "//" and "swift-tools-version":
        assertFailure("//\u{180E}swift-tools-version:5.3\n", "//\u{180E}swift-tools-version:5.3")
        assertFailure("//\u{200B}swift-tools-version:5.3\n", "//\u{200B}swift-tools-version:5.3")
        assertFailure("//\u{200C}swift-tools-version:5.3\n", "//\u{200C}swift-tools-version:5.3")
        assertFailure("//\u{200D}swift-tools-version:5.3\n", "//\u{200D}swift-tools-version:5.3")
        assertFailure("//\u{2060}swift-tools-version:5.3\n", "//\u{2060}swift-tools-version:5.3")
        assertFailure("//\u{FEFF}swift-tools-version:5.3\n", "//\u{FEFF}swift-tools-version:5.3")
    }
    
    /// Verifies that for Swift tools version ≤ 5.3, an error is thrown if anything but a single U+0020 is used as spacing between "//" and "swift-tools-version".
    func testBackwardCompatibilityError() throws {
        
        // MARK: No spacing between "//" and "swift-tools-version" for Swift ≤ 5.3
        
        let specificationsWithZeroSpacing = [
            "//swift-tools-version:3.1"                : "3.1.0",
            "//swift-tools-version:3.1-dev"            : "3.1.0",
            "//swift-tools-version:5.3"                : "5.3.0",
            "//swift-tools-version:5.3.0"              : "5.3.0",
            "//swift-tools-version:5.3-dev"            : "5.3.0",
            "//swift-tools-version:4.8.0"              : "4.8.0",
            "//swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "//swift-tools-version:3.1.2"              : "3.1.2",
            "//swift-tools-version:3.1.2;"             : "3.1.2",
            "//swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "//swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "//swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "//sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in specificationsWithZeroSpacing {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, because there is no spacing between \"//\" and \"swift-tools-version\", and the specified Swift version is less than or equal to 5.3, but no error is thrown."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error else {
                    XCTFail("`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, a differently typed error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "zero spacing between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: 1 character tabulation (U+0009) between "//" and "swift-tools-version"
        
        let specificationsWith1TabAfterSlashes = [
            "//\tswift-tools-version:3.1"                : "3.1.0",
            "//\tswift-tools-version:3.1-dev"            : "3.1.0",
            "//\tswift-tools-version:5.3"                : "5.3.0",
            "//\tswift-tools-version:5.3.0"              : "5.3.0",
            "//\tswift-tools-version:5.3-dev"            : "5.3.0",
            "//\tswift-tools-version:4.8.0"              : "4.8.0",
            "//\tswift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "//\tswift-tools-version:3.1.2"              : "3.1.2",
            "//\tswift-tools-version:3.1.2;"             : "3.1.2",
            "//\tswift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "//\tswift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "//\tswift-toolS-version:3.5.2;hello"        : "3.5.2",
            "//\tsWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in specificationsWith1TabAfterSlashes {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is a horizontal tab character, and the specified Swift version is less than or equal to 5.3, but no error is thrown."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error else {
                    XCTFail("`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, a differently typed error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+0009] between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: 1 space (U+0020) and 1 character tabulation (U+0009) between "//" and "swift-tools-version"
        
        let specificationsWith1SpaceAnd1TabAfterSlashes = [
            "// \tswift-tools-version:3.1"                : "3.1.0",
            "// \tswift-tools-version:3.1-dev"            : "3.1.0",
            "// \tswift-tools-version:5.3"                : "5.3.0",
            "// \tswift-tools-version:5.3.0"              : "5.3.0",
            "// \tswift-tools-version:5.3-dev"            : "5.3.0",
            "// \tswift-tools-version:4.8.0"              : "4.8.0",
            "// \tswift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "// \tswift-tools-version:3.1.2"              : "3.1.2",
            "// \tswift-tools-version:3.1.2;"             : "3.1.2",
            "// \tswift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "// \tswift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "// \tswift-toolS-version:3.5.2;hello"        : "3.5.2",
            "// \tsWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in specificationsWith1SpaceAnd1TabAfterSlashes {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is a horizontal tab character, and the specified Swift version is less than or equal to 5.3, but no error is thrown."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error else {
                    XCTFail("`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, a differently typed error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+0020, U+0009] between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: An assortment of horizontal whitespace characters between "//" and "swift-tools-version"
        
        let specificationsWithAnAssortmentOfWhitespacesAfterSlashes = [
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:3.1"                : "3.1.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:3.1-dev"            : "3.1.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.3"                : "5.3.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.3.0"              : "5.3.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.3-dev"            : "5.3.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:4.8.0"              : "4.8.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:3.1.2"              : "3.1.2",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:3.1.2;"             : "3.1.2",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in specificationsWithAnAssortmentOfWhitespacesAfterSlashes {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is a horizontal tab character, and the specified Swift version is less than or equal to 5.3, but no error is thrown."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error else {
                    XCTFail("`ToolsVersionLoader.Error.invalidSpacingAfterSlashes` should've been thrown, a differently typed error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+00A0, U+1680, U+0009, U+2000, U+2001, U+0020, U+2002, U+202F, U+3000] between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
    }
    
    /// Verifies that if the first line of the manifest is invalid but doesn't contain any pre-defined misspelling, then the Swift tools version defaults to 3.1.
    func testDefault() throws {
        let invalidVersionSpecificationsDefaultedTo3_1 = [
            "//\nswift-tools-version:5.3\n": (3, 1, 0, "3.1.0"),
            "// \nswift-tools-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n swift-tools-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\r\nswift-tools-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n\rswift-tools-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\nswift-tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "// \nswift-tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n swift-tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\r\nswift-tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n\rswift-tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\ntool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "// \ntool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n tool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\r\ntool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n\rtool-version:5.3\n": (3, 1, 0, "3.1.0"),
            "//\nswift-tool:5.3\n": (3, 1, 0, "3.1.0"),
            "// \nswift-tool:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n swift-tool:5.3\n": (3, 1, 0, "3.1.0"),
            "//\r\nswift-tool:5.3\n": (3, 1, 0, "3.1.0"),
            "//\n\rswift-tool:5.3\n": (3, 1, 0, "3.1.0"),
        ]
        
        for (specification, expectedResult) in invalidVersionSpecificationsDefaultedTo3_1 {
            try load(ByteString(encodingAsUTF8: specification)) { toolsVersion in
                XCTAssertEqual(toolsVersion.major, expectedResult.0)
                XCTAssertEqual(toolsVersion.minor, expectedResult.1)
                XCTAssertEqual(toolsVersion.patch, expectedResult.2)
                XCTAssertEqual(toolsVersion.description, expectedResult.3)
            }
        }
        
    }

    func testVersionSpecificManifest() throws {
        let fs = InMemoryFileSystem()
        let root = AbsolutePath("/pkg")
        try fs.createDirectory(root, recursive: true)

        /// Loads the tools version of root pkg.
        func load(_ body: (ToolsVersion) -> Void) {
            body(try! loader.load(at: root, fileSystem: fs))
        }

        // Test default manifest.
        try fs.writeFileContents(root.appending(component: "Package.swift"), bytes: "// swift-tools-version:3.1.1\n")
        load { version in
            XCTAssertEqual(version.description, "3.1.1")
        }

        // Test version specific manifests.
        let keys = Versioning.currentVersionSpecificKeys

        // In case the count ever changes, we will need to modify this test.
        XCTAssertEqual(keys.count, 3)

        // Test the last key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[2]).swift"), bytes: "// swift-tools-version:3.4.1\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.1")
        }

        // Test the second last key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[1]).swift"), bytes: "// swift-tools-version:3.4.0\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.0")
        }

        // Test the first key.
        try fs.writeFileContents(root.appending(component: "Package\(keys[0]).swift"), bytes: "// swift-tools-version:3.4.5\n")
        load { version in
            XCTAssertEqual(version.description, "3.4.5")
        }
    }

    func testVersionSpecificManifestFallbacks() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/pkg/foo"
        )
        let root = AbsolutePath("/pkg")

        try fs.writeFileContents(root.appending(component: "Package.swift"), bytes: "// swift-tools-version:1.0.0\n")
        try fs.writeFileContents(root.appending(component: "Package@swift-4.2.swift"), bytes: "// swift-tools-version:3.4.5\n")
        try fs.writeFileContents(root.appending(component: "Package@swift-15.1.swift"), bytes: "// swift-tools-version:3.4.6\n")
        try fs.writeFileContents(root.appending(component: "Package@swift-15.2.swift"), bytes: "// swift-tools-version:3.4.7\n")
        try fs.writeFileContents(root.appending(component: "Package@swift-15.3.swift"), bytes: "// swift-tools-version:3.4.8\n")

        do {
            let version = try ToolsVersionLoader(currentToolsVersion: ToolsVersion(version: "15.1.1")).load(at: root, fileSystem: fs)
            XCTAssertEqual(version.description, "3.4.6")
        }

        do {
            let version = try ToolsVersionLoader(currentToolsVersion: ToolsVersion(version: "15.2.5")).load(at: root, fileSystem: fs)
            XCTAssertEqual(version.description, "3.4.7")
        }

        do {
            let version = try ToolsVersionLoader(currentToolsVersion: ToolsVersion(version: "3.0.0")).load(at: root, fileSystem: fs)
            XCTAssertEqual(version.description, "1.0.0")
        }

        do {
            let version = try ToolsVersionLoader(currentToolsVersion: ToolsVersion(version: "15.3.0")).load(at: root, fileSystem: fs)
            XCTAssertEqual(version.description, "3.4.8")
        }
    }

    func assertFailure(_ bytes: ByteString, _ theSpecifier: String, file: StaticString = #file, line: UInt = #line) {
        do {
            try load(bytes) {
                XCTFail("unexpected success - \($0)", file: file, line: line)
            }
            XCTFail("unexpected success", file: file, line: line)
        } catch ToolsVersionLoader.Error.malformedToolsVersion(let specifier, _) {
            XCTAssertEqual(specifier, theSpecifier, file: file, line: line)
        } catch {
            XCTFail("Failed with error \(error)")
        }
    }
}
