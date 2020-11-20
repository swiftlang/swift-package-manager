/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension Model.CollectionSource {
    func validate() -> [ValidationError]? {
        var errors: [ValidationError]?
        let appendError = { (error: ValidationError) in
            if errors == nil {
                errors = .init()
            }
            errors?.append(error)
        }

        let allowedSchemes = Set(["https", "file"])

        switch self.type {
        case .json:
            let scheme = url.scheme?.lowercased() ?? ""
            if !allowedSchemes.contains(scheme) {
                appendError(.other(description: "Schema not allowed: \(url.absoluteString)"))
            } else if scheme == "file", !localFileSystem.exists(AbsolutePath(self.url.path)) {
                appendError(.other(description: "Non-local files not allowed: \(url.absoluteString)"))
            }
        }

        return errors
    }
}

internal enum ValidationError: Error, Equatable, CustomStringConvertible {
    case property(name: String, description: String)
    case other(description: String)

    public var description: String {
        switch self {
        case .property(let name, let description):
            return "\(name): \(description)"
        case .other(let description):
            return description
        }
    }
}
