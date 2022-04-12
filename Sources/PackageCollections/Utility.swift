//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel
import SourceControl

struct MultipleErrors: Error, CustomStringConvertible {
    let errors: [Error]
    
    init(_ errors: [Error]) {
        self.errors = errors
    }

    var description: String {
        "\(self.errors)"
    }
}

struct NotFoundError: Error {
    let item: String

    init(_ item: String) {
        self.item = item
    }
}

internal extension Result {
    var failure: Failure? {
        switch self {
        case .failure(let failure):
            return failure
        case .success:
            return nil
        }
    }

    var success: Success? {
        switch self {
        case .failure:
            return nil
        case .success(let value):
            return value
        }
    }
}
