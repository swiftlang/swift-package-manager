/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// Represents a test product which is built and is present on disk.
public struct BuiltTestProduct: Codable {

    /// The name of the package to which the test binary belongs.
    public let packageName: String

    /// The test product name.
    public let productName: String

    /// The path of the test binary.
    public let binaryPath: AbsolutePath

    /// The path of the test bundle.
    public var bundlePath: AbsolutePath {
        // Go up the folder hierarchy until we find the .xctest bundle.
        let hierarchySequence = sequence(first: binaryPath, next: { $0.isRoot ? nil : $0.parentDirectory })
        guard let bundlePath = hierarchySequence.first(where: { $0.basename.hasSuffix(".xctest") }) else {
            fatalError("could not find test bundle path from '\(binaryPath)'")
        }
        
        return bundlePath
    }

    /// Creates a new instance.
    /// - Parameters:
    ///   - packageName: The name of the package to which the test binary belongs.
    ///   - productName: The test product name.
    ///   - binaryPath: The path of the test binary.
    public init(packageName: String, productName: String, binaryPath: AbsolutePath) {
        self.packageName = packageName
        self.productName = productName
        self.binaryPath = binaryPath
    }
}
