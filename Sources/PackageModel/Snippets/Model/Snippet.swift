//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

public struct Snippet {
    public var path: AbsolutePath
    public var explanation: String
    public var presentationCode: String
    public var groupName: String? = nil

    public var name: String {
        path.basenameWithoutExt
    }

    init(parsing source: String, path: AbsolutePath) {
        let extractor = PlainTextSnippetExtractor(source: source)
        self.path = path
        self.explanation = extractor.explanation
        self.presentationCode = extractor.presentationCode
    }

    public init(parsing file: AbsolutePath) throws {
        let source = try String(contentsOf: file.asURL)
        self.init(parsing: source, path: file)
    }
}
