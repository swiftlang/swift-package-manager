//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// A type of module map layout.  Contains all the information needed to generate or use a module map for a target that can have C-style headers.
public enum ModuleMapType: Equatable {
    /// No module map file.
    case none
    /// A custom module map file.
    case custom(AbsolutePath)
    /// An umbrella header included by a generated module map file.
    case umbrellaHeader(AbsolutePath)
    /// An umbrella directory included by a generated module map file.
    case umbrellaDirectory(AbsolutePath)
}

extension ModuleMapType: Codable {
    private enum CodingKeys: String, CodingKey {
        case none, custom, umbrellaHeader, umbrellaDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .custom) {
            self = .custom(path)
        }
        else if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .umbrellaHeader) {
            self = .umbrellaHeader(path)
        }
        else if let path = try container.decodeIfPresent(AbsolutePath.self, forKey: .umbrellaDirectory) {
            self = .umbrellaDirectory(path)
        }
        else {
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            break
        case .custom(let path):
            try container.encode(path, forKey: .custom)
        case .umbrellaHeader(let path):
            try container.encode(path, forKey: .umbrellaHeader)
        case .umbrellaDirectory(let path):
            try container.encode(path, forKey: .umbrellaDirectory)
        }
    }
}
