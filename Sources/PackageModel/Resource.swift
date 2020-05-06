/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

/// An individual resource file and its corresponding rule.
public struct Resource: Hashable, Codable {
    public typealias Rule = TargetDescription.Resource.Rule

    public static let localizationDirectoryExtension = "lproj"

    /// The rule associated with this resource.
    public let rule: Rule

    /// The path of the resource file.
    public let path: AbsolutePath

    /// The localization of the resource.
    public let localization: String?

    /// The relative location of the resource in the resource bundle.
    public var destination: RelativePath {
        if let localization = localization {
            return RelativePath("\(localization).\(Self.localizationDirectoryExtension)/\(path.basename)")
        } else {
            return RelativePath(path.basename)
        }
    }

    public init(rule: Rule, path: AbsolutePath, localization: String?) {
        precondition(rule == .process || localization == nil)
        self.rule = rule
        self.path = path
        self.localization = localization != "Base" ? localization?.lowercased() : localization
    }
}
