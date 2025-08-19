import Basics
import func Build.containsAtMain
import Testing

struct ContainsAtMainReturnsExpectedValueTestData: CustomStringConvertible {
    var description: String {
        self.id
    }

    let fileContent: String
    let expected: Bool
    let knownIssue: Bool
    let id: String
}

@Suite
struct BuildDescriptionTests {
    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: [
            ContainsAtMainReturnsExpectedValueTestData(
                fileContent: """
                """,
                expected: false,
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
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
                knownIssue: false,
                id: "Complex multi-line comment scenario",
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
                expected: true,
                knownIssue: true,
                id: "Multi-line comment end on a line containing @main",
            )
        ],
    )
    func containsAtMainReturnsExpectedValue(
        data: ContainsAtMainReturnsExpectedValueTestData,
    ) async throws {
        let fileContent = data.fileContent
        let expected = data.expected
        let knownIssue = data.knownIssue

        let fileUnderTest = AbsolutePath.root.appending("myfile.swift")
        let fs = InMemoryFileSystem()
        try fs.createDirectory(fileUnderTest.parentDirectory, recursive: true)
        try fs.writeFileContents(fileUnderTest, string: fileContent)

        let actual = try containsAtMain(fileSystem: fs, path: fileUnderTest)

        withKnownIssue {
            #expect(actual == expected)
        } when: {
            knownIssue
        }

    }
}
