/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import class Foundation.ProcessInfo

public struct ContextModel {
    public let packageDirectory : String
    
    public init(packageDirectory : String) {
        self.packageDirectory = packageDirectory
    }
    
    public var environment : [String : String] {
        ProcessInfo.processInfo.environment
    }
}

extension ContextModel : Codable {
    private enum CodingKeys: CodingKey {
        case packageDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packageDirectory = try container.decode(String.self, forKey: .packageDirectory)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageDirectory, forKey: .packageDirectory)
    }

    public var encoded : String {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }

    public static func decode() -> ContextModel {
        // TODO: Look at ProcessInfo.processInfo
        var args = Array(ProcessInfo.processInfo.arguments[1...]).makeIterator()
        while let arg = args.next() {
            if arg == "-context", let json = args.next() {
                let decoder = JSONDecoder()
                let data = json.data(using: .utf8)!
                return (try! decoder.decode(ContextModel.self, from: data))
            }
        }
        fatalError("Could not decode ContextModel parameter.")
    }
}
