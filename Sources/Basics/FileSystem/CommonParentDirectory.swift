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
public func getCommonParentDirectory(paths: [AbsolutePath]) throws-> AbsolutePath {
    // Handle empty array case
    guard !paths.isEmpty else {
        return AbsolutePath.root
    }

    // Handle single path case
    guard paths.count > 1 else {
        return paths[0]
    }

    // Get the components of all paths
    let allComponents = paths.map { $0.components }

    // Find the minimum length to avoid index out of bounds
    let minLength = allComponents.map { $0.count }.min() ?? 0

    // Find the common prefix by comparing components at each position
    var commonComponents: [String] = []

    for index in 0..<minLength {
        let component = allComponents[0][index]

        // Check if this component is the same in all paths
        let isCommon = allComponents.allSatisfy { $0[index] == component }

        if isCommon {
            commonComponents.append(component)
        } else {
            // Stop at the first different component
            break
        }
    }

    // Handle the case where there are no common components beyond root
    guard !commonComponents.isEmpty else {
        return AbsolutePath.root
    }

    // Build the result path from common components
    if commonComponents.count == 1 && commonComponents[0] == "/" {
        return AbsolutePath.root
    }

    // Join the common components back into a path string
    let commonPath = commonComponents.joined(separator: "/")

    // Handle the case where the first component is the root separator
    if commonComponents[0] == "/" {
        if commonComponents.count == 1 {
            return AbsolutePath.root
        }
        // Skip the first "/" component since AbsolutePath constructor expects paths to start with "/"
        let pathWithoutLeadingSlash = commonComponents.dropFirst().joined(separator: "/")
        return try AbsolutePath(validating: "/" + pathWithoutLeadingSlash)
    }

    if !commonPath.starts(with: "/") {
        return try AbsolutePath(validating: "/\(commonPath)")
    }
    return try AbsolutePath(validating: commonPath)
}
