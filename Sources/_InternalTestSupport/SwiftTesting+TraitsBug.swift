/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Testing

extension Trait where Self == Testing.Bug {
    public static func SWBINTTODO(_ comment: Comment) -> Self {
        bug(nil, id: 0, comment)
    }
}

public enum Relationship {
    case verifies
    case defect
    case fixedBy
}

extension Trait where Self == Testing.Bug {
    public static func issue(
        _ issue: _const String,
        relationship: Relationship,
    ) -> Self {
        bug(nil, id: 0, "\(relationship): \(issue)")
    }

    public static var IssueWindowsRelativePathAssert: Self {
        // TSCBasic/Path.swift:969: Assertion failed
        issue(
            "https://github.com/swiftlang/swift-package-manager/issues/8602",
            relationship: .defect,
        )
    }

    public static var IssueWindowsPathLastConponent: Self {
        // $0.path.lastComponent in test code returns fullpaths on Windows
        issue(
            "https://github.com/swiftlang/swift-package-manager/issues/8554",
            relationship: .defect,
        )
    }

    public static var IssueWindowsLongPath: Self {
        .issue(
            // "https://github.com/swiftlang/swift-tools-support-core/pull/521",
            "rdar://157310562",
            relationship: .fixedBy,
        )
    }

    public static var IssueProductTypeForObjectLibraries: Self {
        .issue(
            "https://github.com/swiftlang/swift-build/issues/609",
            relationship: .defect,
        )
    }

    public static var IssueSwiftBuildLinuxRunnable: Self {
        .issue(
            "https://github.com/swiftlang/swift-package-manager/issues/8416",
            relationship: .defect,
        )
    }

    public static var IssueCannnotOpenSharedObjectFileLibSwiftCore : Self {
        // /tmp/Miscellaneous_PackageEdit.H5ku8Q/foo/.build/aarch64-unknown-linux-gnu/Products/Debug-linux/foo: error while loading shared libraries: libswiftCore.so: cannot open shared object file: No such file or directory
        .issue(
            "https://github.com/swiftlang/swift-package-manager/issues/8416",
            relationship: .defect,
        )
    }
}
