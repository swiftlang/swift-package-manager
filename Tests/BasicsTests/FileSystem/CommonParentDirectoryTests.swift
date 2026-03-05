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

#if os(Windows)
private var windows: Bool { true }
#else
private var windows: Bool { false }
#endif

@Suite(
    .tags(
        .TestSize.small,
        .Platform.FileSystem,
    ),
)
struct CommonParentDirectoryTests {

    @Test(
        arguments: [
            // Basic cases
            (id: "identical_paths", paths: ["/a/b/c", "/a/b/c"], expected: "/a/b/c"),
            (id: "simple_siblings", paths: ["/a/b/c", "/a/b/d"], expected: "/a/b"),
            (id: "simple_cousins", paths: ["/a/b/c/d", "/a/b/e/f"], expected: "/a/b"),
            (id: "usr_local_paths", paths: ["/usr/local/bin", "/usr/local/lib"], expected: "/usr/local"),

            // Multiple paths
            (id: "three_user_dirs", paths: ["/home/user/docs", "/home/user/music", "/home/user/videos"], expected: "/home/user"),
            (id: "multiple_descendants", paths: ["/a/b/c/d", "/a/b/e/f", "/a/b/g"], expected: "/a/b"),

            // Different depths
            (id: "ancestor_descendant", paths: ["/a/b", "/a/b/c/d/e"], expected: "/a/b"),
            (id: "descendant_ancestor", paths: ["/a/b/c/d/e", "/a/b"], expected: "/a/b"),

            // Root cases
            (id: "single_root", paths: ["/"], expected: "/"),
            (id: "multiple_roots", paths: ["/", "/"], expected: "/"),
            (id: "root_with_subdir", paths: ["/", "/usr"], expected: "/"),
            (id: "no_common_parent", paths: ["/a/b", "/x/y"], expected: "/"),
            (id: "system_dirs", paths: ["/usr/local", "/var/lib", "/etc/config"], expected: "/"),

            // Complex scenarios
            (id: "project_structure", paths: ["/projects/MyApp/Sources/MyApp/main.swift", "/projects/MyApp/Sources/Utils/helper.swift", "/projects/MyApp/Tests/MyAppTests/test.swift", "/projects/MyApp/Package.swift"], expected: "/projects/MyApp"),
            (id: "var_subdirs", paths: ["/var/log/system/auth.log", "/var/log/system/kernel.log", "/var/log/apache/access.log"], expected: "/var/log"),
            (id: "user_documents", paths: ["/home/alice/documents/work", "/home/alice/documents/personal", "/home/alice/music"], expected: "/home/alice"),

            // Ancestor relationships
            (id: "usr_hierarchy", paths: ["/usr", "/usr/local", "/usr/local/bin", "/usr/lib"], expected: "/usr"),
            (id: "nested_hierarchy", paths: ["/a/b/c/d/e/f", "/a/b/c", "/a/b/c/d/g"], expected: "/a/b/c"),

            // Similar prefixes
            (id: "long_shared_prefix", paths: ["/very/long/shared/path/branch1/file1", "/very/long/shared/path/branch2/file2", "/very/long/shared/path/branch3/subdir/file3"], expected: "/very/long/shared/path"),
            (id: "module_paths", paths: ["/app/module/feature/component.swift", "/app/module/feature", "/app/module/other/file.swift"], expected: "/app/module"),

            // Mixed depth paths
            (id: "mixed_depths", paths: ["/a/b/c/d/e/f/g/h", "/a/b", "/a/b/c/x/y/z", "/a/b/different"], expected: "/a/b"),

            // Single path edge case
            (id: "single_path", paths: ["/home/user/documents"], expected: "/home/user/documents"),

            // System paths
            (id: "system_paths_no_common", paths: ["/usr/local/bin", "/home/user", "/var/log", "/etc/config"], expected: "/"),
            (id: "var_paths", paths: ["/var/log/messages", "/var/cache/apt", "/var/tmp/temp.txt"], expected: "/var"),

            // Identical multiple paths
            (id: "five_identical", paths: ["/home/user/docs", "/home/user/docs", "/home/user/docs", "/home/user/docs", "/home/user/docs"], expected: "/home/user/docs"),

            // Special characters and edge cases
            (id: "paths_with_spaces", paths: ["/home/user/My Documents", "/home/user/My Pictures"], expected: "/home/user"),
            (id: "paths_with_dots", paths: ["/home/user/.config/app", "/home/user/.cache/app"], expected: "/home/user"),
            (id: "paths_with_underscores", paths: ["/var/log/app_error.log", "/var/log/app_debug.log"], expected: "/var/log"),
            (id: "paths_with_hyphens", paths: ["/opt/some-app/bin", "/opt/some-app/lib"], expected: "/opt/some-app"),
            (id: "paths_with_numbers", paths: ["/backup/2023/january", "/backup/2023/february"], expected: "/backup/2023"),
            (id: "mixed_special_chars", paths: ["/projects/app-v1.0_beta/src", "/projects/app-v1.0_beta/test"], expected: "/projects/app-v1.0_beta"),

            // Normalized path scenarios (testing AbsolutePath normalization)
            (id: "paths_with_dot_segments", paths: ["/a/b/./c/d", "/a/b/./e/f"], expected: "/a/b"),
            (id: "paths_with_dotdot_segments", paths: ["/a/b/c/../d", "/a/b/e/../f"], expected: "/a/b"),
            (id: "mixed_normalization", paths: ["/a/b/./c/../d", "/a/b/e/./f"], expected: "/a/b"),

            // Deep nesting scenarios
            (id: "very_deep_paths", paths: ["/a/b/c/d/e/f/g/h/i/j/k/l/m/n", "/a/b/c/d/e/f/g/h/i/j/x/y/z"], expected: "/a/b/c/d/e/f/g/h/i/j"),
            (id: "asymmetric_depths", paths: ["/a", "/a/b/c/d/e/f/g/h/i/j/k/l"], expected: "/a"),

            // File extensions and similar names
            (id: "files_with_extensions", paths: ["/src/main.swift", "/src/utils.swift", "/src/tests.swift"], expected: "/src"),
            (id: "similar_filenames", paths: ["/docs/readme.txt", "/docs/readme.md", "/docs/readme.pdf"], expected: "/docs"),

            // Unicode and international characters (if supported by AbsolutePath)
            (id: "unicode_paths", paths: ["/home/用户/文档", "/home/用户/图片"], expected: "/home/用户"),
        ] as [(String, [String], String)]
    )
    func testGetCommonParentDirectory(id: String, paths: [String], expected: String) throws {
        let absolutePaths = try paths.map { try AbsolutePath(validating: $0) }
        let result = getCommonParentDirectory(paths: absolutePaths)
        let expectedPath = try AbsolutePath(validating: expected)

        #expect(result == expectedPath, "Test case '\(id)': Expected common parent \(expected) but got \(result.pathString)")
    }

    @Test(
        .IssueWindowsPathTestsFailures,
        .requireHostOS(.windows),
        arguments: [
            // Windows-specific path cases
            (id: "windows_drive_same", paths: [#"\Users/John/Documents"#, "/Users/John/Pictures"], expected: (windows ? #"\Users\John"# : "/Users/John")),
            (id: "windows_drive_different", paths: ["/Program Files/App", "/Data/Files"], expected: (windows ? #"\"# : "/")),
            (id: "windows_system_paths", paths: ["/Windows/System32", "/Windows/Temp"], expected: (windows ? #"\Windows"# : "/Windows")),
            (id: "windows_program_files", paths: ["/Program Files/App1", "/Program Files/App2"], expected: (windows ? #"\Program Files"# : "/Program Files")),
            (id: "windows_mixed_separators", paths: [#"\Users\John\Documents"#, "/Users/John/Pictures"], expected: (windows ? #"\Users\John"# : "/Users/John")),
            (id: "windows_deep_hierarchy", paths: ["/Projects/MyApp/Sources/Utils/helper.cpp", "/Projects/MyApp/Tests/UnitTests/test.cpp"], expected: (windows ? #"\Projects\MyApp"# : "/Projects/MyApp")),
            (id: "windows_root_only", paths: ["/", "/", #"\"#], expected: (windows ? #"\"# : "/")),
            (id: "windows_single_drive", paths: [#"\"#], expected: (windows ? #"\"# : "/")),
        ] as [(String, [String], String)]
    )
    func testGetCommonParentDirectoryWindows(id: String, paths: [String], expected: String) throws {
        try withKnownIssue("Windows path handling may need adjustment", isIntermittent: true) {
            let absolutePaths = try paths.map { try AbsolutePath(validating: $0) }
            let result = getCommonParentDirectory(paths: absolutePaths)
            let expectedPath = try AbsolutePath(validating: expected)

            #expect(result == expectedPath, "Windows test case '\(id)': Expected common parent \(expected) but got \(result.pathString)")
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test("Empty array edge case")
    func testGetCommonParentDirectoryEmptyArray() throws {
        let emptyPaths: [AbsolutePath] = []
        let result = getCommonParentDirectory(paths: emptyPaths)

        #expect(result == AbsolutePath.root, "Empty array should return root directory")
    }
}
