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
            // leading newline characters (U+000A), and 1 space (U+0020) between "//" and "swift-tools-version":
            "\n// swift-tools-version:3.1"                            : (3, 1, 0, "3.1.0"),
            "\n\n// swift-tools-version:3.1-dev"                      : (3, 1, 0, "3.1.0"),
            "\n\n\n// swift-tools-version:5.8.0"                      : (5, 8, 0, "5.8.0"),
            "\n\n\n\n// swift-tools-version:5.8.0-dev.al+sha.x"       : (5, 8, 0, "5.8.0"),
            "\n\n\n\n\n// swift-tools-version:3.1.2"                  : (3, 1, 2, "3.1.2"),
            "\n\n\n\n\n\n// swift-tools-version:3.1.2;"               : (3, 1, 2, "3.1.2"),
            "\n\n\n\n\n\n\n// swift-tools-vErsion:3.1.2;;;;;"         : (3, 1, 2, "3.1.2"),
            "\n\n\n\n\n\n\n\n// swift-tools-version:3.1.2;x;x;x;x;x;" : (3, 1, 2, "3.1.2"),
            "\n\n\n\n\n\n\n\n\n// swift-toolS-version:3.5.2;hello"    : (3, 5, 2, "3.5.2"),
            "\n\n\n\n\n\n\n\n\n\n// sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n" : (3, 5, 2, "3.5.2"),
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
            // Some leading line terminators, and no spacing between "//" and "swift-tools-version" for Swift > 5.3:
            "\u{A}//swift-tools-version:5.4"                 : (5, 4, 0, "5.4.0"),
            "\u{B}//swift-tools-version:5.4-dev"             : (5, 4, 0, "5.4.0"),
            "\u{C}//swift-tools-version:5.8.0"               : (5, 8, 0, "5.8.0"),
            "\u{D}//swift-tools-version:5.8.0-dev.al+sha.x"  : (5, 8, 0, "5.8.0"),
            "\u{D}\u{A}//swift-tools-version:6.1.2"          : (6, 1, 2, "6.1.2"),
            "\u{85}//swift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "\u{2028}//swift-tools-vErsion:6.1.2;;;;;"       : (6, 1, 2, "6.1.2"),
            "\u{2029}//swift-tools-version:6.1.2;x;x;x;x;x;" : (6, 1, 2, "6.1.2"),
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-toolS-version:5.5.2;hello"  : (5, 5, 2, "5.5.2"),
            "\u{A}\u{A}\u{B}\u{B}\u{C}\u{C}\u{D}\u{D}\u{D}\u{A}\u{D}\u{A}\u{85}\u{85}\u{2028}\u{2028}\u{2029}\u{2029}//sWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n" : (5, 5, 2, "5.5.2"),
            // Some leading line terminators, and 1 space (U+0020) between "//" and "swift-tools-version" for Swift > 5.3:
            "\u{A}// swift-tools-version:5.4"                 : (5, 4, 0, "5.4.0"),
            "\u{B}// swift-tools-version:5.4-dev"             : (5, 4, 0, "5.4.0"),
            "\u{C}// swift-tools-version:5.8.0"               : (5, 8, 0, "5.8.0"),
            "\u{D}// swift-tools-version:5.8.0-dev.al+sha.x"  : (5, 8, 0, "5.8.0"),
            "\u{D}\u{A}// swift-tools-version:6.1.2"          : (6, 1, 2, "6.1.2"),
            "\u{85}// swift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "\u{2028}// swift-tools-vErsion:6.1.2;;;;;"       : (6, 1, 2, "6.1.2"),
            "\u{2029}// swift-tools-version:6.1.2;x;x;x;x;x;" : (6, 1, 2, "6.1.2"),
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}// swift-toolS-version:5.5.2;hello"  : (5, 5, 2, "5.5.2"),
            "\u{A}\u{A}\u{B}\u{B}\u{C}\u{C}\u{D}\u{D}\u{D}\u{A}\u{D}\u{A}\u{85}\u{85}\u{2028}\u{2028}\u{2029}\u{2029}// sWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n" : (5, 5, 2, "5.5.2"),
            // Some leading line terminators, and 1 character tabulation (U+0009) between "//" and "swift-tools-version" for Swift > 5.3:
            "\u{A}//\tswift-tools-version:5.4"                 : (5, 4, 0, "5.4.0"),
            "\u{B}//\tswift-tools-version:5.4-dev"             : (5, 4, 0, "5.4.0"),
            "\u{C}//\tswift-tools-version:5.8.0"               : (5, 8, 0, "5.8.0"),
            "\u{D}//\tswift-tools-version:5.8.0-dev.al+sha.x"  : (5, 8, 0, "5.8.0"),
            "\u{D}\u{A}//\tswift-tools-version:6.1.2"          : (6, 1, 2, "6.1.2"),
            "\u{85}//\tswift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "\u{2028}//\tswift-tools-vErsion:6.1.2;;;;;"       : (6, 1, 2, "6.1.2"),
            "\u{2029}//\tswift-tools-version:6.1.2;x;x;x;x;x;" : (6, 1, 2, "6.1.2"),
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\tswift-toolS-version:5.5.2;hello"  : (5, 5, 2, "5.5.2"),
            "\u{A}\u{A}\u{B}\u{B}\u{C}\u{C}\u{D}\u{D}\u{D}\u{A}\u{D}\u{A}\u{85}\u{85}\u{2028}\u{2028}\u{2029}\u{2029}//\tsWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n" : (5, 5, 2, "5.5.2"),
            // Some leading line terminators, and 1 character tabulation (U+0009) followed by 1 space (U+0020) between "//" and "swift-tools-version" for Swift > 5.3:
            "\u{A}// \tswift-tools-version:5.4"                 : (5, 4, 0, "5.4.0"),
            "\u{B}// \tswift-tools-version:5.4-dev"             : (5, 4, 0, "5.4.0"),
            "\u{C}// \tswift-tools-version:5.8.0"               : (5, 8, 0, "5.8.0"),
            "\u{D}// \tswift-tools-version:5.8.0-dev.al+sha.x"  : (5, 8, 0, "5.8.0"),
            "\u{D}\u{A}// \tswift-tools-version:6.1.2"          : (6, 1, 2, "6.1.2"),
            "\u{85}// \tswift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "\u{2028}// \tswift-tools-vErsion:6.1.2;;;;;"       : (6, 1, 2, "6.1.2"),
            "\u{2029}// \tswift-tools-version:6.1.2;x;x;x;x;x;" : (6, 1, 2, "6.1.2"),
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}// \tswift-toolS-version:5.5.2;hello"  : (5, 5, 2, "5.5.2"),
            "\u{A}\u{A}\u{B}\u{B}\u{C}\u{C}\u{D}\u{D}\u{D}\u{A}\u{D}\u{A}\u{85}\u{85}\u{2028}\u{2028}\u{2029}\u{2029}// \tsWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n" : (5, 5, 2, "5.5.2"),
            // Some leading line terminators, and an assortment of horizontal whitespace characters between "//" and "swift-tools-version" for Swift > 5.3:
            "\u{A}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.4"                 : (5, 4, 0, "5.4.0"),
            "\u{B}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.4-dev"             : (5, 4, 0, "5.4.0"),
            "\u{C}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.8.0"               : (5, 8, 0, "5.8.0"),
            "\u{D}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:5.8.0-dev.al+sha.x"  : (5, 8, 0, "5.8.0"),
            "\u{D}\u{A}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2"          : (6, 1, 2, "6.1.2"),
            "\u{85}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2;"             : (6, 1, 2, "6.1.2"),
            "\u{2028}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-vErsion:6.1.2;;;;;"       : (6, 1, 2, "6.1.2"),
            "\u{2029}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-tools-version:6.1.2;x;x;x;x;x;" : (6, 1, 2, "6.1.2"),
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}swift-toolS-version:5.5.2;hello"  : (5, 5, 2, "5.5.2"),
            "\u{A}\u{A}\u{B}\u{B}\u{C}\u{C}\u{D}\u{D}\u{D}\u{A}\u{D}\u{A}\u{85}\u{85}\u{2028}\u{2028}\u{2029}\u{2029}//\u{A0}\u{1680}\t\u{2000}\u{2001} \u{2002}\u{202F}\u{3000}sWiFt-tOoLs-vErSiOn:5.5.2\nkkk\n" : (5, 5, 2, "5.5.2"),
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
    
    /// Verifies that the correct error is thrown for each manifest missing its Swift tools version specification.
    func testMissingSpecifications() throws {
        /// Leading snippets of manifest files that don't have Swift tools version specifications.
        let manifestSnippetsWithoutSpecification = [
            "",
            "\n",
            "\n\r\r\n",
            "ni",
            "\rimport PackageDescription",
            "let package = Package(\n",
        ]
        
        for manifestSnippet in manifestSnippetsWithoutSpecification {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the Swift tools version specification is missing from the manifest snippet"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.commentMarker(.isMissing)) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.commentMarker(.isMissing))' should've been thrown, but a different error is thrown")
                    return
                }
                
                XCTAssertEqual(
                    error.description,
                    "the manifest is missing a Swift tools version specification; consider prepending to the manifest '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current Swift toolchain version as the lowest supported version by the project; if such a specification already exists, consider moving it to the top of the manifest, or prepending it with '//' to help Swift Package Manager find it"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each Swift tools version specification missing its comment marker.
    func testMissingSpecificationCommentMarkers() throws {
        let manifestSnippetsWithoutSpecificationCommentMarker = [
            " swift-tools-version:4.0",
            // Missing comment markers are diagnosed before missing Labels.
            " 4.2",
            // Missing comment markers are diagnosed before missing version specifiers.
            " swift-tools-version:",
            " ",
            // Missing comment markers are diagnosed before misspelt labels.
            " Swift toolchain version 5.1",
            " shiny-tools-version",
            // Missing comment markers are diagnosed before misspelt version specifiers.
            " swift-tools-version:0",
            " The Answer to the Ultimate Question of Life, the Universe, and Everything is 42",
            " 9999999",
            // Missing comment markers are diagnosed before backward-compatibility checks.
            "\n\n\nswift-tools-version:3.1\r",
            "\r\n\r\ncontrafibularity",
            "\n\r\t3.14",
            "",
        ]
        
        for manifestSnippet in manifestSnippetsWithoutSpecificationCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the comment marker is missing from the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.commentMarker(.isMissing)) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.commentMarker(.isMissing))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the manifest is missing a Swift tools version specification; consider prepending to the manifest '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current Swift toolchain version as the lowest supported version by the project; if such a specification already exists, consider moving it to the top of the manifest, or prepending it with '//' to help Swift Package Manager find it"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each Swift tools version specification missing its label.
    func testMissingSpecificationLabels() throws {
        let manifestSnippetsWithoutSpecificationLabel = [
            "// 5.3",
            // Missing labels are diagnosed before missing version specifiers.
            "// ",
            // Missing labels are diagnosed before misspelt comment markers.
            "/// ",
            "/* ",
            // Missing labels are diagnosed before misspelt version specifiers.
            "// 6 × 9 = 42",
            "/// 99 little bugs in the code",
            // Missing labels are diagnosed before backward-compatibility checks.
            "\r\n// ",
            "//",
            "\n\r///\t2.1\r",
        ]
        
        for manifestSnippet in manifestSnippetsWithoutSpecificationLabel {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the label is missing from the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.label(.isMissing)) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.label(.isMissing))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the Swift tools version specification is missing a label; consider inserting 'swift-tools-version:' between the comment marker and the version specifier"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each Swift tools version specification missing its version specifier.
    func testMissingVersionSpecifiers() throws {
        let manifestSnippetsWithoutVersionSpecifier = [
            "// swift-tools-version:",
            // Missing version specifiers are diagnosed before misspelt comment markers.
            "/// swift-tools-version:",
            "/* swift-tools-version:",
            // Missing version specifiers are diagnosed before misspelt labels.
            "// swallow tools version:",
            "/// We are the knights who say 'Ni!'",
            // Missing version specifiers are diagnosed before backward-compatibility checks.
            "\r\n//\tswift-tools-version:",
            "\n\r///The swifts hung in the sky in much the same way that bricks don't.\u{85}",
        ]
        
        for manifestSnippet in manifestSnippetsWithoutVersionSpecifier {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the version specifier is missing from the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.versionSpecifier(.isMissing)) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.versionSpecifier(.isMissing))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the Swift tools version specification is missing a version specifier; consider appending '\(ToolsVersion.currentToolsVersion)' to the line to specify the current Swift toolchain version as the lowest supported version by the project"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each misspelt comment marker in Swift tools version specification.
    func testMisspeltSpecificationCommentMarkers() throws {
        let manifestSnippetsWithMisspeltSpecificationCommentMarker = [
            "/// swift-tools-version:4.0",
            "/** swift-tools-version:4.1",
            // Misspelt comment markers are diagnosed before misspelt labels.
            "//// Shiny toolchain version 4.2",
            // Misspelt comment markers are diagnosed before misspelt version specifiers.
            "/* swift-tools-version:43",
            "/** Swift version 4.4 **/",
            // Misspelt comment markers are diagnosed before backward-compatibility checks.
            "\r\r\r*/swift-tools-version:4.5",
            "\n\n\n/*/*\t\tSwift5\r",
        ]
        
        for manifestSnippet in manifestSnippetsWithMisspeltSpecificationCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the comment marker is misspelt in the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.commentMarker(.isMisspelt(let misspeltCommentMarker))) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.commentMarker(.isMisspelt))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the comment marker '\(misspeltCommentMarker)' is misspelt for the Swift tools version specification; consider replacing it with '//'"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each misspelt label in Swift tools version specification.
    func testMisspeltSpecificationLabels() throws {
        let manifestSnippetsWithMisspeltSpecificationLabel = [
            "// fast-tools-version:3.0",
            // Misspelt labels are diagnosed before misspelt version specifiers.
            "// rapid-tools-version:3",
            "// swift-too1s-version:3.0",
            // Misspelt labels are diagnosed before backward-compatibility checks.
            "\n\r//\t\u{A0}prompt-t00ls-version:3.0.0.0\r\n",
        ]
        
        for manifestSnippet in manifestSnippetsWithMisspeltSpecificationLabel {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the label is misspelt in the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.label(.isMisspelt(let misspeltLabel))) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.label(.isMisspelt))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the Swift tools version specification's label '\(misspeltLabel)' is misspelt; consider replacing it with 'swift-tools-version:'"
                )
            }
        }
    }
    
    /// Verifies that the correct error is thrown for each misspelt version specifier in Swift tools version specification.
    func testMisspeltVersionSpecifiers() throws {
        let manifestSnippetsWithMisspeltVersionSpecifier = [
            "// swift-tools-version:5²",
            "// swift-tools-version:5⃣️.2⃣️",
            "// swift-tools-version:5 ÷ 2 = 2.5",
            // Misspelt version specifiers are diagnosed before backward-compatibility checks.
            "\u{A}\u{B}\u{C}\u{D}//\u{3000}swift-tools-version:五.二\u{2028}",
        ]
        
        for manifestSnippet in manifestSnippetsWithMisspeltVersionSpecifier {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: manifestSnippet)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the version specifier is misspelt in the Swift tools version specification"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt(let misspeltVersionSpecifier))) = error else {
                    XCTFail("'ToolsVersionLoader.Error.malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt))' should've been thrown, but a different error is thrown")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "the Swift tools version '\(misspeltVersionSpecifier)' is misspelt or otherwise invalid; consider replacing it with '\(ToolsVersion.currentToolsVersion)' to specify the current Swift toolchain version as the lowest supported version by the project"
                )
            }
        }
    }
    
    /// Verifies that a correct error is thrown, if the manifest is valid for Swift tools version > 5.3, but invalid for version ≤ 5.3.
    func testBackwardIncompatibilityPre5_3_1() throws {
        
        // The order of tests in this function:
        // 1. Test leading line terminators that are invalid for Swift ≤ 5.3.
        // 2. Test that backward-incompatible leading line terminators are diagnosed before backward-incompatible spacings after the comment marker.
        // 3. Test spacings after the comment marker.
        
        // MARK: 1 leading u+000D
        
        let manifestSnippetWith1LeadingCarriageReturn = [
            "\u{D}//swift-tools-version:3.1"                : "3.1.0",
            "\u{D}//swift-tools-version:3.1-dev"            : "3.1.0",
            "\u{D}//swift-tools-version:5.3"                : "5.3.0",
            "\u{D}//swift-tools-version:5.3.0"              : "5.3.0",
            "\u{D}//swift-tools-version:5.3-dev"            : "5.3.0",
            "\u{D}//swift-tools-version:4.8.0"              : "4.8.0",
            "\u{D}//swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "\u{D}//swift-tools-version:3.1.2"              : "3.1.2",
            "\u{D}//swift-tools-version:3.1.2;"             : "3.1.2",
            "\u{D}//swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "\u{D}//swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "\u{D}//swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "\u{D}//sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in manifestSnippetWith1LeadingCarriageReturn {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the manifest starts with a U+000D, and the specified version \(toolsVersionString) (≤ 5.3) supports only 0 or 1 leading U+000A."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.leadingLineTerminators, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.leadingLineTerminators, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "leading line terminator sequence [U+000D] in manifest is supported by only Swift > 5.3; for the specified version \(toolsVersionString), only newline characters (U+000A) at the beginning of the manifest is supported; consider moving the Swift tools version specification to the first line of the manifest"
                )
            }
        }
        
        // MARK: 1 leading U+000D followed by 1 U+000A
        
        let manifestSnippetWith1LeadingCarriageReturnFollowedBy1LineFeed = [
            "\u{D}\u{A}//swift-tools-version:3.1"                : "3.1.0",
            "\u{D}\u{A}//swift-tools-version:3.1-dev"            : "3.1.0",
            "\u{D}\u{A}//swift-tools-version:5.3"                : "5.3.0",
            "\u{D}\u{A}//swift-tools-version:5.3.0"              : "5.3.0",
            "\u{D}\u{A}//swift-tools-version:5.3-dev"            : "5.3.0",
            "\u{D}\u{A}//swift-tools-version:4.8.0"              : "4.8.0",
            "\u{D}\u{A}//swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "\u{D}\u{A}//swift-tools-version:3.1.2"              : "3.1.2",
            "\u{D}\u{A}//swift-tools-version:3.1.2;"             : "3.1.2",
            "\u{D}\u{A}//swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "\u{D}\u{A}//swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "\u{D}\u{A}//swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "\u{D}\u{A}//sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in manifestSnippetWith1LeadingCarriageReturnFollowedBy1LineFeed {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the manifest starts with a U+000D followed by a U+000A, and the specified version \(toolsVersionString) (≤ 5.3) supports only 0 or 1 leading U+000A."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.leadingLineTerminators, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.leadingLineTerminators, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "leading line terminator sequence [U+000D, U+000A] in manifest is supported by only Swift > 5.3; for the specified version \(toolsVersionString), only newline characters (U+000A) at the beginning of the manifest is supported; consider moving the Swift tools version specification to the first line of the manifest"
                )
            }
        }
        
        // MARK: An assortment of leading line terminators
        
        let manifestSnippetWithAnAssortmentOfLeadingLineTerminators = [
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:3.1"                : "3.1.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:3.1-dev"            : "3.1.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:5.3"                : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:5.3.0"              : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:5.3-dev"            : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:4.8.0"              : "4.8.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:3.1.2"              : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:3.1.2;"             : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in manifestSnippetWithAnAssortmentOfLeadingLineTerminators {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the manifest starts with an assortment of line terminators, and the specified version \(toolsVersionString) (≤ 5.3) supports only 0 or 1 leading U+000A."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.leadingLineTerminators, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.leadingLineTerminators, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "leading line terminator sequence [U+000A, U+000B, U+000C, U+000D, U+000D, U+000A, U+0085, U+2028, U+2029] in manifest is supported by only Swift > 5.3; for the specified version \(toolsVersionString), only newline characters (U+000A) at the beginning of the manifest is supported; consider moving the Swift tools version specification to the first line of the manifest"
                )
            }
        }
        
        // MARK: An assortment of leading line terminators and an assortment of horizontal whitespace characters between "//" and "swift-tools-version"
        
        let manifestSnippetWithAnAssortmentOfLeadingLineTerminatorsAndAnAssortmentOfWhitespacesAfterSpecifcationCommentMarker = [
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1"                : "3.1.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1-dev"            : "3.1.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3"                : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3.0"              : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3-dev"            : "5.3.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:4.8.0"              : "4.8.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2"              : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2;"             : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "\u{A}\u{B}\u{C}\u{D}\u{D}\u{A}\u{85}\u{2028}\u{2029}//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        // Backward-incompatible leading line terminators are diagnosed before backward-incompatible spacings after the comment marker.
        // So the error thrown here should be about invalid leading line terminators, although both the line terminators and the spacing here are backward-incompatible.
        for (specification, toolsVersionString) in manifestSnippetWithAnAssortmentOfLeadingLineTerminatorsAndAnAssortmentOfWhitespacesAfterSpecifcationCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the manifest starts with an assortment of line terminators, and the specified version \(toolsVersionString) (≤ 5.3) supports only 0 or 1 leading U+000A."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.leadingLineTerminators, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.leadingLineTerminators, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "leading line terminator sequence [U+000A, U+000B, U+000C, U+000D, U+000D, U+000A, U+0085, U+2028, U+2029] in manifest is supported by only Swift > 5.3; for the specified version \(toolsVersionString), only newline characters (U+000A) at the beginning of the manifest is supported; consider moving the Swift tools version specification to the first line of the manifest"
                )
            }
        }
        
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
                "a 'ToolsVersionLoader.Error' should've been thrown, because there is no spacing between '//' and 'swift-tools-version', and the specified version \(toolsVersionString) (≤ 5.3) supports exactly 1 space (U+0020) between '//' and 'swift-tools-version'"
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "zero spacing between '//' and 'swift-tools-version' is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: 1 character tabulation (U+0009) between "//" and "swift-tools-version"
        
        let specificationsWith1TabAfterCommentMarker = [
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
        
        for (specification, toolsVersionString) in specificationsWith1TabAfterCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is a character tabulation (U+0009), and the specified version \(toolsVersionString) (≤ 5.3) supports exactly 1 space (U+0020) between \"//\" and \"swift-tools-version\"."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+0009] between '//' and 'swift-tools-version' is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: 1 space (U+0020) and 1 character tabulation (U+0009) between "//" and "swift-tools-version"
        
        let specificationsWith1SpaceAnd1TabAfterCommentMarker = [
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
        
        for (specification, toolsVersionString) in specificationsWith1SpaceAnd1TabAfterCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is a space (U+0020) and a character tabulation (U+0009), and the specified version \(toolsVersionString) (≤ 5.3) supports exactly 1 space (U+0020) between \"//\" and \"swift-tools-version\"."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+0020, U+0009] between '//' and 'swift-tools-version' is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
            }
        }
        
        // MARK: An assortment of horizontal whitespace characters between "//" and "swift-tools-version"
        
        let specificationsWithAnAssortmentOfWhitespacesAfterCommentMarker = [
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1"                : "3.1.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1-dev"            : "3.1.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3"                : "5.3.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3.0"              : "5.3.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:5.3-dev"            : "5.3.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:4.8.0"              : "4.8.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:4.8.0-dev.al+sha.x" : "4.8.0",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2"              : "3.1.2",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2;"             : "3.1.2",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-vErsion:3.1.2;;;;;"         : "3.1.2",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-tools-version:3.1.2;x;x;x;x;x;"   : "3.1.2",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}swift-toolS-version:3.5.2;hello"        : "3.5.2",
            "//\u{9}\u{20}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}sWiFt-tOoLs-vErSiOn:3.5.2\nkkk\n"       : "3.5.2",
        ]
        
        for (specification, toolsVersionString) in specificationsWithAnAssortmentOfWhitespacesAfterCommentMarker {
            XCTAssertThrowsError(
                try load(ByteString(encodingAsUTF8: specification)),
                "a 'ToolsVersionLoader.Error' should've been thrown, because the spacing between \"//\" and \"swift-tools-version\" is an assortment of horizontal whitespace characters, and the specified version \(toolsVersionString) (≤ 5.3) supports exactly 1 space (U+0020) between \"//\" and \"swift-tools-version\"."
            ) { error in
                guard let error = error as? ToolsVersionLoader.Error, case .backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _) = error else {
                    XCTFail("'ToolsVersionLoader.Error.backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker, _)' should've been thrown, but a different error is thrown.")
                    return
                }
                XCTAssertEqual(
                    error.description,
                    "horizontal whitespace sequence [U+0009, U+0020, U+00A0, U+1680, U+2000, U+2001, U+2002, U+2003, U+2004, U+2005, U+2006, U+2007, U+2008, U+2009, U+200A, U+202F, U+205F, U+3000] between '//' and 'swift-tools-version' is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(toolsVersionString)"
                )
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
    
}
