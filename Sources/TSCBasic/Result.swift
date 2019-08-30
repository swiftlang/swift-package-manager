/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A type erased error enum.
public struct AnyError: Swift.Error, CustomStringConvertible {
    /// The underlying error.
    public let underlyingError: Swift.Error

    public init(_ error: Swift.Error) {
        // If we already have any error, don't nest it.
        if case let error as AnyError = error {
            self = error
        } else {
            self.underlyingError = error
        }
    }

    public var description: String {
        return String(describing: underlyingError)
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

// AnyError specific helpers.
extension Result where Failure == AnyError {
    /// Initialise with something that throws AnyError.
    public init(anyError body: () throws -> Success) {
        do {
            self = .success(try body())
        } catch {
            self = .failure(AnyError(error))
        }
    }

    /// Initialise with an error, it will be automatically converted to AnyError.
    public init(_ error: Swift.Error) {
        self = .failure(AnyError(error))
    }

    /// Evaluates the given throwing closure when this Result instance has a value.
    ///
    /// The final result will either be the transformed value or any error thrown by the closure.
    public func mapAny<U>(_ transform: (Success) throws -> U) -> Result<U, AnyError> {
        switch self {
        case .success(let value):
            do {
                return Result<U, AnyError>.success(try transform(value))
            } catch {
                return Result<U, AnyError>(error)
            }
        case .failure(let error):
            return Result<U, AnyError>(error)
        }
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
