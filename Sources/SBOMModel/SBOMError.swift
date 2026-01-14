//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

// MARK: - General SBOM Errors

/// General errors that can occur across SBOM operations
internal enum SBOMError: Error, LocalizedError, CustomStringConvertible {
    /// Expected a specific SBOM spec type but got another
    case unexpectedSpecType(expected: String, actual: Spec)
    case failedToWriteSBOM

    internal var errorDescription: String? {
        switch self {
        case .unexpectedSpecType(let expected, let actual):
            "Expected \(expected) spec but got \(actual)"
        case .failedToWriteSBOM:
            "Failed to write SBOM"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM error"
    }
}

// MARK: - Command Errors

/// Errors that can occur during the SBOM generation command
package enum SBOMCommandError: Error, LocalizedError {
    case noSpecArg
    case targetFlagNotSupported
    
    public var errorDescription: String? {
        switch self {
        case .noSpecArg:
            return "No SBOM specification argument provided. Use --sbom-spec to specify the SBOM format."
        case .targetFlagNotSupported:
            return "--sbom-spec cannot be used with --target flag"
        }
    }
}
// MARK: - Schema Errors

/// Errors that can occur during SBOM schema operations
internal enum SBOMSchemaError: Error, LocalizedError, CustomStringConvertible {
    /// Schema file not found in bundle
    case schemaFileNotFound(filename: String, bundlePath: String)
    /// Invalid JSON schema format
    case invalidSchemaFormat(message: String)
    /// Bundle not found (validation will be skipped)
    case bundleNotFound(bundleName: String)
    
    internal var errorDescription: String? {
        switch self {
        case .schemaFileNotFound(let filename, let bundlePath):
            "SBOM schema file '\(filename).json' not found in bundle: \(bundlePath)"
        case .invalidSchemaFormat(let message):
            "Invalid JSON schema format: \(message)"
        case .bundleNotFound(let bundleName):
            "Bundle '\(bundleName)' with schemas not found"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM schema error"
    }
}

// MARK: - Converter Errors

/// Errors that can occur during SBOM format conversion
internal enum SBOMConverterError: Error, LocalizedError, CustomStringConvertible {
    /// Missing required metadata for conversion
    case missingRequiredMetadata(message: String)

    internal var errorDescription: String? {
        switch self {
        case .missingRequiredMetadata(let message):
            "Missing required metadata: \(message)"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM converter error"
    }
}

// MARK: - Extractor Errors

/// Errors that can occur during SBOM data extraction
internal enum SBOMExtractorError: Error, LocalizedError, CustomStringConvertible {
    /// No root package found in package graph
    case noRootPackage(context: String)
    /// No build graph available
    case noBuildGraph(context: String)
    /// Product not found in package
    case productNotFound(productName: String, packageIdentity: String)
    internal var errorDescription: String? {
        switch self {
        case .noRootPackage(let context):
            "No root package found in package graph, cannot \(context)"
        case .noBuildGraph(let context):
            "No build graph available, cannot \(context)"
        case .productNotFound(let productName, let packageIdentity):
            "Product '\(productName)' not found in root package '\(packageIdentity)'"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM extractor error"
    }
}

// MARK: - Encoder Errors

/// Errors that can occur during SBOM encoding
internal enum SBOMEncoderError: Error, LocalizedError, CustomStringConvertible {
    /// Failed to convert SBOM to JSON object
    case jsonConversionFailed(message: String)
    internal var errorDescription: String? {
        switch self {
        case .jsonConversionFailed(let message):
            "Failed to convert SBOM to JSON: \(message)"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM encoder error"
    }
}

// MARK: - Validator Errors

/// Errors that can occur during SBOM validation
internal enum SBOMValidatorError: Error, LocalizedError, CustomStringConvertible {
    /// Value does not match 'not' schema (should not match)
    case notSchemaViolation(path: String, valueDescription: String)
    /// Type mismatch during validation
    case typeMismatch(path: String, expected: String, actual: String, debugInfo: String)
    /// Missing required property
    case missingRequired(path: String, property: String)
    /// Invalid value
    case invalidValue(path: String, message: String)
    /// Schema composition error (oneOf, anyOf, allOf)
    case schemaComposition(path: String, message: String)
    /// Constraint violation (min/max, pattern, etc.)
    case constraintViolation(path: String, message: String)
    internal var errorDescription: String? {
        switch self {
        case .notSchemaViolation(let path, let valueDescription):
            "Value at \(path) matches 'not' schema (should not match). Value: \(valueDescription)"
        case .typeMismatch(let path, let expected, let actual, let debugInfo):
            "Type mismatch at \(path): expected \(expected), got \(actual) (\(debugInfo))"
        case .missingRequired(let path, let property):
            "Missing required property '\(property)' at \(path)"
        case .invalidValue(let path, let message):
            "Invalid value at \(path): \(message)"
        case .schemaComposition(let path, let message):
            "Schema composition error at \(path): \(message)"
        case .constraintViolation(let path, let message):
            "Constraint violation at \(path): \(message)"
        }
    }

    internal var description: String {
        self.errorDescription ?? "Unknown SBOM validator error"
    }
}
