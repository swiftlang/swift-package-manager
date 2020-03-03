/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Result where Failure == Error {
    public func tryMap<NewSuccess>(_ closure: (Success) throws -> NewSuccess) -> Result<NewSuccess, Error> {
        flatMap({ value in
            Result<NewSuccess, Error>(catching: {
                try closure(value)
            })
        })
    }
}

/// Represents a string error.
public struct StringError: Equatable, Codable, CustomStringConvertible, Error {

    /// The description of the error.
    public let description: String

    /// Create an instance of StringError.
    public init(_ description: String) {
        self.description = description
    }
}

extension Result where Failure == StringError {
    /// Create an instance of Result<Value, StringError>.
    ///
    /// Errors will be encoded as StringError using their description.
    public init(string body: () throws -> Success) {
        do {
            self = .success(try body())
        } catch let error as StringError {
            self = .failure(error)
        } catch {
            self = .failure(StringError(String(describing: error)))
        }
    }
}
