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

/// Returns the common parent directory of the given absolute paths.
///
/// This function finds the deepest directory that is an ancestor of all the provided paths.
/// If the paths have no common ancestor other than the root directory, it returns the root.
/// If the array is empty, it returns the root directory.
///
/// - Parameter paths: An array of absolute paths to find the common parent for
/// - Returns: The common parent directory as an AbsolutePath
///
/// Examples:
/// - `["/a/b/c", "/a/b/d"]` → `"/a/b"`
/// - `["/usr/local/bin", "/usr/local/lib"]` → `"/usr/local"`
/// - `["/a/b", "/x/y"]` → `"/"`
/// - `[]` → `"/"`
public func getCommonParentDirectory(paths: [AbsolutePath]) throws -> AbsolutePath {
    guard let first = paths.first else {
        return AbsolutePath.root
    }

    var common = first
    for path in paths.dropFirst() {
        while !common.isAncestorOfOrEqual(to: path) {
            if common.isRoot {
                return common
            }
            common = common.parentDirectory
        }
    }
    return common
}
