/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// An simple enum which is either a value or an error.
/// It can be used for error handling in situations where try catch is
/// problematic to use, for eg: asynchronous APIs.
public enum Result<Value, ErrorType: Swift.Error> {
    /// Indicates success with value in the associated object.
    case success(Value)

    /// Indicates failure with error inside the associated object.
    case failure(ErrorType)

    /// Initialiser for value.
    public init(_ value: Value) {
        self = .success(value)
    }

    /// Initialiser for error.
    public init(_ error: ErrorType) {
        self = .failure(error)
    }

    /// Initialise with something that can throw ErrorType.
    public init(_ body: () throws -> Value) throws {
        do {
            self = .success(try body())
        } catch let error as ErrorType {
            self = .failure(error)
        }
    }

    /// Get the value if success else throw the saved error.
    public func dematerialize() throws -> Value {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

extension Result: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success(let value):
            return "Result(\(value))"
        case .failure(let error):
            return "Result(\(error))"
        }
    }
}

/// A type erased error enum.
public struct AnyError: Swift.Error, CustomStringConvertible  {
    /// The underlying error.
    public let underlyingError: Swift.Error

    public init(_ error: Swift.Error) {
        self.underlyingError = error
    }

    public var description: String {
        return String(describing: underlyingError)
    }
}
