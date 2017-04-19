/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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

    /// Evaluates the given closure when this Result instance has a value.
    public func map<U>(_ transform: (Value) throws -> U) rethrows -> Result<U, ErrorType> {
        switch self {
        case .success(let value):
            return Result<U, ErrorType>(try transform(value))
        case .failure(let error):
            return Result<U, ErrorType>(error)
        }
    }

    /// Evaluates the given closure when this Result instance has a value, passing the unwrapped value as a parameter.
    ///
    /// The closure returns a Result instance itself which can have value or not.
    public func flatMap<U>(_ transform: (Value) -> Result<U, ErrorType>) -> Result<U, ErrorType> {
        switch self {
            case .success(let value):
                return transform(value)
            case .failure(let error):
                return Result<U, ErrorType>(error)
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

// AnyError specific helpers.
extension Result where ErrorType == AnyError {
    /// Initialise with something that throws AnyError.
    public init(anyError body: () throws -> Value) {
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
    public func mapAny<U>(_ transform: (Value) throws -> U) -> Result<U, AnyError> {
        switch self {
        case .success(let value):
            do {
                return Result<U, AnyError>(try transform(value))
            } catch {
                return Result<U, AnyError>(error)
            }
        case .failure(let error):
            return Result<U, AnyError>(error)
        }
    }
}
