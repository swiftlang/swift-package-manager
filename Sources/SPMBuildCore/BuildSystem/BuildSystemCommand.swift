//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

public struct BuildSystemCommand: Hashable {
    public let name: String
    public let targetName: String?
    public let description: String
    public let verboseDescription: String?
    public let serializedDiagnosticPaths: [AbsolutePath]

    public init(name: String, targetName: String? = nil, description: String, verboseDescription: String? = nil, serializedDiagnosticPaths: [AbsolutePath] = []) {
        self.name = name
        self.targetName = targetName
        self.description = description
        self.verboseDescription = verboseDescription
        self.serializedDiagnosticPaths = serializedDiagnosticPaths
    }
}
