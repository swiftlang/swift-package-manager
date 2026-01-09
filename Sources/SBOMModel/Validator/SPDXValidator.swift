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

import Foundation

struct SPDXValidator: SBOMValidatorProtocol {
    enum SPDXKeys {
        static let context = "@context"
        static let graph = "@graph"
        static let id = "@id"
        static let spdxId = "spdxId"
    }

    private let validator: SBOMValidator
    private let graphElementSchema: [String: Any]

    init(schema: [String: Any]) {
        self.validator = SBOMValidator(schema: schema)
        self.graphElementSchema = SPDXValidator.extractGraphElementSchema(from: schema)
    }

    func validate(_ jsonObject: Any) async throws {
        guard let rootDict = jsonObject as? [String: Any] else {
            throw SBOMValidatorError.typeMismatch(
                path: "$",
                expected: "dictionary",
                actual: "other",
                debugInfo: "Expected dictionary for SPDX JSON-LD document"
            )
        }
        guard let contextString = rootDict[SPDXKeys.context] as? String,
              !contextString.isEmpty
        else {
            throw SBOMValidatorError.invalidValue(path: "$", message: "@context must be a non-empty string")
        }
        guard let graph = rootDict[SPDXKeys.graph] as? [Any],
              !graph.isEmpty
        else {
            throw SBOMValidatorError.invalidValue(path: "$", message: "@graph must be a non-empty array")
        }

        for (index, element) in graph.enumerated() {
            try await self.validateValue(element, path: "$[@graph][\(index)]")
        }
    }

    func validateValue(_ value: Any, path: String) async throws {
        if let dictObject = value as? [String: Any] {
            try await self.validateObjectWithSPDXRules(dictObject, path: path)
        }
        try await self.validator.validateValue(value, path: path, schema: self.graphElementSchema)
    }

    private func validateObjectWithSPDXRules(_ object: [String: Any], path: String) async throws {
        let schema = self.validator.schema

        if let required = schema["required"] as? [String] {
            for property in required {
                if property == SPDXKeys.context {
                    continue
                }
                // allow @id as substitute for spdxId
                if property == SPDXKeys.spdxId && object[SPDXKeys.id] != nil {
                    continue
                }
                guard object[property] != nil else {
                    throw SBOMValidatorError.missingRequired(path: path, property: property)
                }
            }
        }

        if let properties = schema["properties"] as? [String: [String: Any]] {
            for (key, value) in object {
                let propertySchema: [String: Any]?

                // @id can use spdxId schema
                if key == SPDXKeys.id, let spdxIdSchema = properties[SPDXKeys.spdxId] {
                    propertySchema = spdxIdSchema
                }
                // skip spdxId if @id is present
                else if key == SPDXKeys.spdxId && object[SPDXKeys.id] != nil {
                    continue
                } else {
                    propertySchema = properties[key]
                }
                if let propSchema = propertySchema {
                    try await self.validator.validateValue(value, path: "\(path).\(key)", schema: propSchema)
                }
            }
        }

        if let oneOf = schema["oneOf"] as? [[String: Any]] {
            try await self.validator.validateOneOf(object, schemas: oneOf, path: path)
        }
    }

    private static func extractGraphElementSchema(from schema: [String: Any]) -> [String: Any] {
        // Graph elements use AnyClass schema (oneOf[1]) rather than root schema
        if let oneOf = schema[SBOMValidator.SchemaKeys.oneOf] as? [[String: Any]], oneOf.count > 1 {
            return oneOf[1]
        } else if let anyOf = schema[SBOMValidator.SchemaKeys.anyOf] as? [[String: Any]], !anyOf.isEmpty {
            return anyOf[0]
        }
        return schema
    }
}
