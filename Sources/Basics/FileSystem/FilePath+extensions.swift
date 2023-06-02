//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SystemPackage

extension FilePath {
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    var pathString: String {
        self.isEmpty ? "." : self.string
    }

    /// Directory component.  An absolute path always has a non-empty directory
    /// component (the directory component of the root path is the root itself).
    var dirname: String {
        self.removingLastComponent().pathString
    }

    /// Last path component (including the suffix, if any).  it is never empty.
    var basename: String {
        self.lastComponent?.pathString ?? self.root?.pathString ?? "."
    }

    /// Returns the basename without the extension.
    var basenameWithoutExt: String {
        self.lastComponent?.stem ?? self.root?.pathString ?? "."
    }

    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix, nor is a
    /// trailing `.` character.
    var suffix: String? {
        if let ext = self.extension {
            return "." + ext
        } else {
            return .none
        }
    }

    /// Absolute path of parent directory.  This always returns a path, because
    /// every directory has a parent (the parent directory of the root directory
    /// is considered to be the root directory itself).
    var parentDirectory: Self {
        self.removingLastComponent()
    }

    func appending(_ components: [String]) -> Self {
        self.appending(components.filter{ !$0.isEmpty }.map(FilePath.Component.init))
    }

    var componentsAsString: [String] {
        self.components.map{ $0.pathString }
    }
}


extension FilePath.Component {
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    var pathString: String {
        self.string.isEmpty ? "." : self.string
    }
}

extension FilePath.Root {
    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    var pathString: String {
        self.string.isEmpty ? "." : self.string
    }
}
