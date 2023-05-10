//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// An individual resource file and its corresponding rule.
public struct Resource: Codable, Equatable {
    public static let localizationDirectoryExtension = "lproj"

    /// The rule associated with this resource.
    public let rule: Rule

    /// The path of the resource file.
    public let path: AbsolutePath

    /// The relative location of the resource in the resource bundle.
    public var destination: RelativePath {
        get throws {
            switch self.rule {
            case .process(.some(let localization)):
                return try RelativePath(validating: "\(localization).\(Self.localizationDirectoryExtension)/\(path.basename)")
            default:
                return try RelativePath(validating: path.basename)
            }
        }
    }

    public init(rule: Rule, path: AbsolutePath) {
        var rule = rule
        if case .process(.some(let localization)) = rule, localization != "Base" {
            rule  = .process(localization: localization.lowercased())
        }
        self.rule = rule
        self.path = path
    }

    public enum Rule: Codable, Equatable {
        case process(localization: String?)
        case copy
        case embedInCode
    }
}
