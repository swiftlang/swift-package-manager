/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// The context a Swift package is running in. This encapsulates states that are known at build-time.
/// For example where in the file system the current package resides.
@available(_PackageDescription, introduced: 5.6)
public struct Context {
    private let model : ContextModel

    /// The directory containing Package.swift.
    public var packageDirectory : String {
        model.packageDirectory
    }
    
    /// Snapshot of the system environment variables.
    public var environment : [String : String] {
        model.environment
    }
    
    private init(_ model : ContextModel) {
        self.model = model
    }

    /// Singleton accessor. There is only one Context instance.
    public static let current = Context(ContextModel.decode())
}
