/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public struct BuildSystemCommand: Hashable {
    public let name: String
    public let description: String
    public let verboseDescription: String?

    public init(name: String, description: String, verboseDescription: String? = nil) {
        self.name = name
        self.description = description
        self.verboseDescription = verboseDescription
    }
}
