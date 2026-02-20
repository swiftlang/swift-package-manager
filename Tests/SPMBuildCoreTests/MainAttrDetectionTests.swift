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
import Basics
import SPMBuildCore
import Testing

struct ContainsAtMainReturnsExpectedValueTestData: CustomStringConvertible {
    var description: String {
        self.id
    }

    let fileContent: String
    let expected: Bool
    let id: String
}

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct MainAttrDetectionTests {
    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: [
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                """,
                expected: false,
                id: "Empty file",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "Simple @main case",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                    @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "@main with leading whitespace",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                // @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "@main in single-line comment (should be ignored)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                struct MyApp {
                    // This is @main but not at start
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "@main not at beginning of line (should not match)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                import Foundation
                import SwiftUI

                @main
                struct MyApp: App {
                    var body: some Scene {
                        WindowGroup {
                            ContentView()
                        }
                    }
                }
                """,
                expected: true,
                id: "@main with imports and other code",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                @main
                struct FirstApp {
                    static func main() {
                        print("First")
                    }
                }

                // @main (commented out)
                struct SecondApp {
                    static func main() {
                        print("Second")
                    }
                }
                """,
                expected: true,
                id: "Multiple @main occurrences (first one should be detected)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                @main
                struct MyApp {
                    static func main() {
                        let text = "@main is cool"
                        print(text)
                    }
                }
                """,
                expected: true,
                id: "@main in string literal (should still match as it's at line start)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "No @main, just regular code",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                \t  @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "@main with tabs and spaces",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /*
                @main
                */
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "@main in multi-line comment (should be ignored)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /* @main */
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "@main in multi-line comment on same line (should be ignored)",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /*
                Some comment
                */
                @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "@main after multi-line comment ends",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                // This is a comment
                /* Multi-line
                   comment */
                @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "@main with mixed comments",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /*
                This is a multi-line comment
                that spans multiple lines
                @main should be ignored here
                */

                @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "Complex multi-line comment scenario",
            ),
        ],
    )
    func containsAtMainReturnsExpectedValue(
        data: ContainsAtMainReturnsExpectedValueTestData,
    ) async throws {
        try await self._testImplementation_containsAtMainReturnsExpectedValue(data: data)
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9685", relationship: .defect),
        arguments: [
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /*
                This is a multi-line comment
                */ @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: true,
                id: "Multi-line comment end on same line as @main",
            ),
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                /*
                This is a multi-line comment
                /* @main
                struct MyApp {
                    static func main() {
                        print("Hello, World!")
                    }
                }
                """,
                expected: false,
                id: "Nested comment opening with @main (still inside comment)",
            ),
        ],
    )
    func containsAtMainIssue9685(
        data: ContainsAtMainReturnsExpectedValueTestData,
    ) async throws {
        try await self._testImplementation_containsAtMainReturnsExpectedValue(data: data)
    }

    fileprivate func _testImplementation_containsAtMainReturnsExpectedValue(
        data: ContainsAtMainReturnsExpectedValueTestData,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let fileContent = data.fileContent
        let expected = data.expected

        let fileUnderTest = AbsolutePath.root.appending("myfile.swift")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(fileUnderTest.parentDirectory, recursive: true)
        try fs.writeFileContents(fileUnderTest, string: fileContent)

        let actual = try containsAtMain(fileSystem: fs, path: fileUnderTest)

        #expect(actual == expected, sourceLocation: sourceLocation)
    }
}
