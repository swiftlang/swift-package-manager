/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Codable wrapper for Result
public struct CodableResult<Success, Failure>: Codable where Success: Codable, Failure: Codable & Error {
    private enum CodingKeys: String, CodingKey {
        case success, failure
    }
    
    public let result: Result<Success, Failure>
    public init(result: Result<Success, Failure>) {
        self.result = result
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self.result {
        case .success(let value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .success)
            try unkeyedContainer.encode(value)
        case .failure(let error):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .failure)
            try unkeyedContainer.encode(error)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .success:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(Success.self)
            self.init(result: .success(value))
        case .failure:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let error = try unkeyedValues.decode(Failure.self)
            self.init(result: .failure(error))
        }
    }
}

extension CodableResult where Failure == StringError {
    public init(body: () throws -> Success) {
        do {
            self.init(result: .success(try body()))
        } catch let error as StringError {
            self.init(result: .failure(error))
        } catch {
            self.init(result: .failure(StringError(String(describing: error))))
        }
    }
}
