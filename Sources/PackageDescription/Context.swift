//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The context information for a Swift package.
///
/// The context encapsulates states that are known when Swift Package Manager interprets the package manifest,
/// for example the location in the file system where the current package resides.
@available(_PackageDescription, introduced: 5.6)
public struct Context {
    private static let model = try! ContextModel.decode()

    /// The directory that contains `Package.swift`.
    public static var packageDirectory : String {
        model.packageDirectory
    }
    
    /// Snapshot of the system environment variables.
    public static var environment : [String : String] {
        model.environment
    }
    
    private init() {
    }
}
