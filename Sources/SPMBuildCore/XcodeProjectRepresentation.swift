/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics

/// Represents a simplifed view of an Xcode project to a plugin.
public struct XcodeProjectRepresentation: Equatable, Hashable {
    public var displayName: String
    public var directoryPath: AbsolutePath
    public var filePaths: [AbsolutePath]
    public var targets: [Target]
    
    public init(displayName: String, directoryPath: AbsolutePath, filePaths: [AbsolutePath], targets: [Target]) {
        self.displayName = displayName
        self.directoryPath = directoryPath
        self.filePaths = filePaths
        self.targets = targets
    }
    
    public struct Target: Equatable, Hashable {
        public var displayName: String
        public var product: Product?
        public var inputFiles: [InputFile]
        
        public init(displayName: String, product: Product?, inputFiles: [InputFile]) {
            self.displayName = displayName
            self.product = product
            self.inputFiles = inputFiles
        }

        public struct Product: Equatable, Hashable {
            public var name: String
            public var kind: Kind
            
            public init(name: String, kind: Kind) {
                self.name = name
                self.kind = kind
            }

            /// Represents a kind of product produced by an Xcode target.
            public enum Kind: Equatable, Hashable {
                case application
                case executable
                case framework
                case library
                case other(String)
            }
        }

        public struct InputFile: Equatable, Hashable {
            public var path: AbsolutePath
            public var role: Role
            
            public init(path: AbsolutePath, role: Role) {
                self.path = path
                self.role = role
            }

            public enum Role: Equatable, Hashable {
                case source
                case header
                case resource
                case unknown
            }
        }
    }
}
