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

/// Cache for storing compiled regex patterns (to avoid redundant compilation)
/// Note: Using NSRegularExpression instead of Swift's native Regex type for Windows compatibility.
/// Windows Swift toolchain currently lacks _StringProcessing module support, which causes linker errors
/// with symbols like __imp_$sSS17_StringProcessing14RegexComponent0C7BuilderMc
internal actor SBOMRegexCache {
    private var cache: [String: NSRegularExpression] = [:]
    
    internal func get(_ pattern: String) -> NSRegularExpression? {
        self.cache[pattern]
    }
    
    internal func set(_ pattern: String, regex: NSRegularExpression) {
        self.cache[pattern] = regex
    }
}

/// Cache for storing resolved schema references (to avoid redundant traversals)
internal actor SBOMSchemaReferenceCache {
    private var cache: [String: [String: Any]] = [:]
    
    internal func get(_ reference: String) -> [String: Any]? {
        self.cache[reference]
    }
    
    internal func set(_ reference: String, schema: [String: Any]) {
        self.cache[reference] = schema
    }
}


// TODO: echeng3805
// use a library? or maybe move this all to test code?
// MARK: - Base Validator

struct SBOMValidator: SBOMValidatorProtocol {
    // MARK: - Constants
    
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // Note: Using NSRegularExpression for Windows compatibility (see SBOMRegexCache comment)
    private static let emailRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", options: [])
    private static let regexCache = SBOMRegexCache()
    private static let referenceCache = SBOMSchemaReferenceCache()

    enum StringFormat: String {
        case dateTime = "date-time"
        case date
        case email
        case idnEmail = "idn-email"
        case uri
        case iriReference = "iri-reference"

        func validate(_ value: String, path: String) throws {
            switch self {
            case .dateTime:
                if SBOMValidator.iso8601Formatter.date(from: value) == nil {
                    throw SBOMValidatorError.invalidValue(path: path, message: "invalid date-time format")
                }
            case .date:
                if SBOMValidator.dateFormatter.date(from: value) == nil {
                    throw SBOMValidatorError.invalidValue(path: path, message: "invalid date format")
                }
            case .email, .idnEmail:
                let range = NSRange(location: 0, length: value.utf16.count)
                if SBOMValidator.emailRegex.firstMatch(in: value, options: [], range: range) == nil {
                    throw SBOMValidatorError.invalidValue(path: path, message: "invalid email format")
                }
            case .uri, .iriReference:
                if URL(string: value) == nil {
                    throw SBOMValidatorError.invalidValue(path: path, message: "invalid URI format")
                }
            }
        }
    }

    enum SchemaKeys {
        static let type = "type"
        static let required = "required"
        static let properties = "properties"
        static let items = "items"
        static let enumKey = "enum"
        static let pattern = "pattern"
        static let format = "format"
        static let ref = "$ref"
        static let oneOf = "oneOf"
        static let anyOf = "anyOf"
        static let allOf = "allOf"
        static let const = "const"
        static let not = "not"
        static let additionalProperties = "additionalProperties"
        static let unevaluatedProperties = "unevaluatedProperties"
        static let minimum = "minimum"
        static let maximum = "maximum"
        static let minLength = "minLength"
        static let maxLength = "maxLength"
        static let minItems = "minItems"
        static let maxItems = "maxItems"
        static let uniqueItems = "uniqueItems"
    }

    let schema: [String: Any]

    init(schema: [String: Any]) {
        self.schema = schema
    }

    // MARK: - SBOMValidatorProtocol Implementation

    func validate(_ jsonObject: Any) async throws {
        try await self.validateValue(jsonObject, path: "$")
    }

    func validateValue(_ value: Any, path: String) async throws {
        try await self.validateValue(value, path: path, schema: self.schema)
    }

    func validateValue(_ value: Any, path: String, schema: [String: Any]) async throws {
        if let expectedType = schema[SchemaKeys.type] as? String {
            try self.validateType(value, expectedType: expectedType, path: path)
        }

        if let constValue = schema[SchemaKeys.const] {
            try self.validateConst(value, expectedValue: constValue, path: path)
        }
        if let enumValues = schema[SchemaKeys.enumKey] as? [Any] {
            try self.validateEnum(value, allowedValues: enumValues, path: path)
        }
        try self.validateNumberIfNeeded(value, schema: schema, path: path)


        if let ref = schema[SchemaKeys.ref] as? String {
            try await self.validateReference(value, ref: ref, path: path, schema: schema)
        }
        if let oneOf = schema[SchemaKeys.oneOf] as? [[String: Any]] {
            try await self.validateOneOf(value, schemas: oneOf, path: path)
        }
        if let anyOf = schema[SchemaKeys.anyOf] as? [[String: Any]] {
            try await self.validateAnyOf(value, schemas: anyOf, path: path)
        }
        if let allOf = schema[SchemaKeys.allOf] as? [[String: Any]] {
            try await self.validateAllOf(value, schemas: allOf, path: path)
        }
        if let notSchema = schema[SchemaKeys.not] as? [String: Any] {
            try await self.validateNot(value, schema: notSchema, path: path)
        }

        try await self.validateObjectIfNeeded(value, schema: schema, path: path)
        try await self.validateArrayIfNeeded(value, schema: schema, path: path)
        try await self.validateStringIfNeeded(value, schema: schema, path: path)
    }

    // MARK: - Type Validation

    private func validateType(_ value: Any, expectedType: String, path: String) throws {
        let (actualType, debugInfo) = self.determineActualType(value)
        if expectedType == "number" && actualType == "integer" {
            return
        }
        guard actualType == expectedType else {
            throw SBOMValidatorError.typeMismatch(
                path: path,
                expected: expectedType,
                actual: actualType,
                debugInfo: debugInfo
            )
        }
    }

    private func determineActualType(_ value: Any) -> (type: String, debugInfo: String) {
        switch value {
        case let string as String:
            return ("string", "value: \"\(string)\"")
        case let number as NSNumber where isBoolean(number):
            return ("boolean", "value: \(number.boolValue)")
        case let number as NSNumber where isFloatType(number):
            return ("number", "value: \(number.doubleValue)")
        case let number as NSNumber:
            return ("integer", "value: \(number.intValue)")
        case let array as [Any]:
            return ("array", "length: \(array.count)")
        case let dict as [String: Any]:
            let keys = dict.keys.sorted().joined(separator: ", ")
            return ("object", "keys: \(keys)")
        case is NSNull:
            return ("null", "null")
        default:
            return ("unknown", "type: \(type(of: value))")
        }
    }

    private func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return number === kCFBooleanTrue as NSNumber || number === kCFBooleanFalse as NSNumber
        #else
        // On Linux, check the objCType to determine if it's a boolean
        let objCType = String(cString: number.objCType)
        return objCType == "c" || objCType == "B"
        #endif
    }
    
    private func isFloatType(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFNumberIsFloatType(number)
        #else
        // On Linux, check the objCType to determine if it's a floating point type
        let objCType = String(cString: number.objCType)
        return objCType == "f" || objCType == "d"
        #endif
    }

    // MARK: - Schema Composition Validation

    private func validateReference(_ value: Any, ref: String, path: String, schema: [String: Any]) async throws {
        guard ref.hasPrefix("#/") else { return }

        let pointer = String(ref.dropFirst(2))
        let components = pointer.components(separatedBy: "/")

        // References starting with #/ are always resolved from the root schema (self.schema)
        // not from the current schema being validated
        guard let referencedSchema = await resolveReference(components: components, in: self.schema) else {
            throw SBOMValidatorError.invalidValue(path: path, message: "Could not resolve reference '\(ref)'")
        }

        try await self.validateValue(value, path: path, schema: referencedSchema)
    }

    func validateOneOf(_ value: Any, schemas: [[String: Any]], path: String) async throws {
        var validCount = 0
        var validationErrors: [String] = []
        var matchingSchemas: [Int] = []

        for (index, schema) in schemas.enumerated() {
            do {
                try await self.validateValue(value, path: path, schema: schema)
                validCount += 1
                matchingSchemas.append(index)
            } catch {
                validationErrors.append("Schema \(index): \(error.localizedDescription)")
            }
        }

        if validCount != 1 {
            let valueDesc = self.describeValue(value, maxLength: 200)
            if validCount == 0 {
                let allErrors = validationErrors.joined(separator: "\n  ")
                throw SBOMValidatorError.schemaComposition(
                    path: path,
                    message: "Value does not match any oneOf schemas.\nValue: \(valueDesc)\nErrors:\n  \(allErrors)"
                )
            } else {
                let matchingIndices = matchingSchemas.map(String.init).joined(separator: ", ")
                throw SBOMValidatorError.schemaComposition(
                    path: path,
                    message: "Value matches multiple oneOf schemas (expected exactly one). Matched \(validCount) schemas at indices: \(matchingIndices)\nValue: \(valueDesc)"
                )
            }
        }
    }

    private func validateAnyOf(_ value: Any, schemas: [[String: Any]], path: String) async throws {
        var schemaNames: [String] = []

        for (index, schema) in schemas.enumerated() {
            do {
                try await self.validateValue(value, path: path, schema: schema)
                return // Successfully validated against one schema, we're done
            } catch {
                // Extract just the schema name/type for concise error reporting
                let schemaName = self.extractSchemaName(from: schema, index: index)
                schemaNames.append(schemaName)
            }
        }

        // None of the schemas matched
        let valueDesc = self.describeValue(value, maxLength: 200)

        // Show concise list of attempted schemas
        let summary: String
        if schemaNames.count > 15 {
            let shown = schemaNames.prefix(10).joined(separator: ", ")
            summary = "Tried \(schemaNames.count) schemas: \(shown), ... and \(schemaNames.count - 10) more"
        } else {
            summary = "Tried schemas: \(schemaNames.joined(separator: ", "))"
        }

        throw SBOMValidatorError.schemaComposition(
            path: path,
            message: "Value does not match any anyOf schemas.\nValue: \(valueDesc)\n\(summary)"
        )
    }

    private func validateAllOf(_ value: Any, schemas: [[String: Any]], path: String) async throws {
        var errors: [String] = []

        for (index, schema) in schemas.enumerated() {
            do {
                try await self.validateValue(value, path: path, schema: schema)
            } catch {
                errors.append("Schema \(index): \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            let valueDesc = self.describeValue(value, maxLength: 200)
            let allErrors = errors.joined(separator: "\n  ")
            throw SBOMValidatorError.schemaComposition(
                path: path,
                message: "Value does not match all allOf schemas.\nValue: \(valueDesc)\nErrors:\n  \(allErrors)"
            )
        }
    }

    private func validateNot(_ value: Any, schema: [String: Any], path: String) async throws {
        do {
            try await self.validateValue(value, path: path, schema: schema)
            let valueDesc = self.describeValue(value, maxLength: 200)
            throw SBOMValidatorError.notSchemaViolation(path: path, valueDescription: valueDesc)
        } catch let error as SBOMValidatorError { // rethrow notSchemaViolation errors (from nested "not" schemas)
            if case .notSchemaViolation = error {
                throw error
            }
            return
        } catch { // rethrow unexpected errors (parsing errors, system errors, programming bugs)
            throw error
        }
    }

    // MARK: - Value Validation

    private func validateConst(_ value: Any, expectedValue: Any, path: String) throws {
        if !self.areEqual(value, expectedValue) {
            let valueDesc = self.describeValue(value)
            let expectedDesc = self.describeValue(expectedValue)
            throw SBOMValidatorError.invalidValue(
                path: path,
                message: "Value does not match const. Expected: \(expectedDesc), got: \(valueDesc)"
            )
        }
    }

    private func validateEnum(_ value: Any, allowedValues: [Any], path: String) throws {
        let isValid = allowedValues.contains { allowedValue in
            self.areEqual(value, allowedValue)
        }

        if !isValid {
            let valueStr = self.describeValue(value)
            let allowedStr = allowedValues.map { self.describeValue($0) }.joined(separator: ", ")
            throw SBOMValidatorError.invalidValue(
                path: path,
                message: "Value is not one of the allowed enum values. Got: \(valueStr), allowed: [\(allowedStr)]"
            )
        }
    }

    // MARK: - Type-Specific Validation - Object

    private func validateObjectIfNeeded(_ value: Any, schema: [String: Any], path: String) async throws {
        guard let objectValue = value as? [String: Any] else { return }

        // Collect all schema metadata in a single traversal pass
        let metadata = await self.collectSchemaMetadata(from: schema)
        
        // Validate required properties
        if !metadata.required.isEmpty {
            try self.validateRequiredProperties(objectValue, required: metadata.required, path: path)
        }

        // Validate object properties
        if !metadata.properties.isEmpty {
            try await self.validateObjectProperties(objectValue, properties: metadata.properties, path: path)
        }

        // Validate additional and unevaluated properties
        try await self.validateAdditionalProperties(objectValue, schema: schema, path: path, allowedProperties: metadata.allowedProperties)
        try await self.validateUnevaluatedProperties(objectValue, schema: schema, path: path, evaluatedProperties: metadata.evaluatedProperties)
    }

    private func validateRequiredProperties(_ object: [String: Any], required: [String], path: String) throws {
        for property in required {
            guard object[property] != nil else {
                throw SBOMValidatorError.missingRequired(path: path, property: property)
            }
        }
    }

    private func validateObjectProperties(
        _ object: [String: Any],
        properties: [String: [String: Any]],
        path: String
    ) async throws {
        for (key, value) in object {
            guard let propertySchema = properties[key] else {
                continue
            }
            try await self.validateValue(value, path: "\(path).\(key)", schema: propertySchema)
        }
    }

    private func validateAdditionalProperties(_ object: [String: Any], schema: [String: Any], path: String, allowedProperties: Set<String>) async throws {
        guard let additionalProps = schema[SchemaKeys.additionalProperties] else { return }

        let extraProperties = Set(object.keys).subtracting(allowedProperties)

        if let allowsAdditional = additionalProps as? Bool, !allowsAdditional {
            guard extraProperties.isEmpty else {
                let extraList = extraProperties.sorted().joined(separator: ", ")
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Additional properties not allowed: \(extraList)"
                )
            }
            return
        }

        guard let additionalPropsSchema = additionalProps as? [String: Any] else { return }

        for key in extraProperties {
            guard let value = object[key] else { continue }
            try await self.validateValue(value, path: "\(path).\(key)", schema: additionalPropsSchema)
        }
    }

    private func validateUnevaluatedProperties(_ object: [String: Any], schema: [String: Any], path: String, evaluatedProperties: Set<String>) async throws {
        guard let unevaluatedProps = schema[SchemaKeys.unevaluatedProperties] as? Bool,
              !unevaluatedProps
        else {
            return
        }

        let unevaluated = Set(object.keys).subtracting(evaluatedProperties)

        guard unevaluated.isEmpty else {
            let unevaluatedList = unevaluated.sorted().joined(separator: ", ")
            throw SBOMValidatorError.constraintViolation(
                path: path,
                message: "Unevaluated properties found: \(unevaluatedList)"
            )
        }
    }

    // MARK: - Type-Specific Validation - Array

    private func validateArrayIfNeeded(_ value: Any, schema: [String: Any], path: String) async throws {
        guard let arrayValue = value as? [Any] else { return }

        if let items = schema[SchemaKeys.items] as? [String: Any] {
            try await self.validateArrayItems(arrayValue, itemSchema: items, path: path)
        }
        try self.validateArrayConstraints(arrayValue, schema: schema, path: path)
    }

    private func validateArrayItems(_ array: [Any], itemSchema: [String: Any], path: String) async throws {
        for (index, item) in array.enumerated() {
            try await self.validateValue(item, path: "\(path)[\(index)]", schema: itemSchema)
        }
    }

    private func validateArrayConstraints(_ array: [Any], schema: [String: Any], path: String) throws {
        if let minItems = schema["minItems"] as? Int {
            guard array.count >= minItems else {
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Array has fewer items than minimum. Expected at least \(minItems), got \(array.count)"
                )
            }
        }

        if let maxItems = schema["maxItems"] as? Int {
            guard array.count <= maxItems else {
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Array has more items than maximum. Expected at most \(maxItems), got \(array.count)"
                )
            }
        }

        if let uniqueItems = schema["uniqueItems"] as? Bool, uniqueItems {
            try self.validateUniqueItems(array, path: path)
        }
    }

    private func validateUniqueItems(_ array: [Any], path: String) throws {
        var seen = Set<String>()

        for (index, item) in array.enumerated() {
            // Create a canonical representation of the item for comparison
            let itemKey = try canonicalRepresentation(of: item)

            if seen.contains(itemKey) {
                let itemDesc = self.describeValue(item, maxLength: 100)
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Array contains duplicate items. Duplicate found at index \(index): \(itemDesc)"
                )
            }
            seen.insert(itemKey)
        }
    }

    private func canonicalRepresentation(of value: Any) throws -> String {
        // Convert value to a canonical JSON string for comparison
        // This handles objects, arrays, strings, numbers, booleans, and null
        if let dict = value as? [String: Any] {
            // Sort keys for consistent comparison
            let sortedData = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            return String(data: sortedData, encoding: .utf8) ?? ""
        } else if let array = value as? [Any] {
            let data = try JSONSerialization.data(withJSONObject: array, options: [])
            return String(data: data, encoding: .utf8) ?? ""
        } else if let string = value as? String {
            return "\"\(string)\""
        } else if let number = value as? NSNumber {
            if self.isBoolean(number) {
                return number.boolValue ? "true" : "false"
            }
            return "\(number)"
        } else if value is NSNull {
            return "null"
        }
        return "\(value)"
    }

    // MARK: - Type-Specific Validation - String

    private func validateStringIfNeeded(_ value: Any, schema: [String: Any], path: String) async throws {
        guard let stringValue = value as? String else { return }

        try self.validateStringLength(stringValue, schema: schema, path: path)

        if let pattern = schema[SchemaKeys.pattern] as? String {
            try await self.validatePattern(stringValue, pattern: pattern, path: path)
        }
        if let format = schema[SchemaKeys.format] as? String {
            try self.validateFormat(stringValue, format: format, path: path)
        }
    }

    private func validateStringLength(_ value: String, schema: [String: Any], path: String) throws {
        let minLength = schema[SchemaKeys.minLength] as? Int
        let maxLength = schema[SchemaKeys.maxLength] as? Int
        let length = value.count
        if let min = minLength, length < min {
            throw SBOMValidatorError.constraintViolation(
                path: path,
                message: "String \(value) is shorter than minimum length. Expected at least \(min), got \(length)"
            )
        }
        if let max = maxLength, length > max {
            throw SBOMValidatorError.constraintViolation(
                path: path,
                message: "String \(value) is longer than maximum length. Expected at most \(max), got \(length)"
            )
        }
    }

    private func validatePattern(_ value: String, pattern: String, path: String) async throws {
        let regex = try await Self.getCachedRegex(for: pattern, path: path)
        
        let range = NSRange(location: 0, length: value.utf16.count)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              match.range.location == 0,
              match.range.length == value.utf16.count else {
            throw SBOMValidatorError.constraintViolation(
                path: path,
                message: "String does not match pattern: \(pattern). Value: \"\(value)\""
            )
        }
    }
    
    /// Get a cached compiled regex pattern, or compile and cache it if not present
    /// Note: Using NSRegularExpression for Windows compatibility (see SBOMRegexCache comment)
    private static func getCachedRegex(for pattern: String, path: String) async throws -> NSRegularExpression {
        // Check cache first
        if let cached = await regexCache.get(pattern) {
            return cached
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw SBOMValidatorError.invalidValue(path: path, message: "Invalid regex pattern: \(pattern)")
        }
        await regexCache.set(pattern, regex: regex)
        return regex
    }

    private func validateFormat(_ value: String, format: String, path: String) throws {
        guard let stringFormat = StringFormat(rawValue: format) else {
            // JSON Schema allows unknown formats
            return
        }
        try stringFormat.validate(value, path: path)
    }

    // MARK: - Type-Specific Validation - Number

    private func validateNumberIfNeeded(_ value: Any, schema: [String: Any], path: String) throws {
        guard let numberValue = value as? NSNumber else { return }
        try self.validateNumericConstraints(numberValue, schema: schema, path: path)
    }

    private func validateNumericConstraints(_ value: NSNumber, schema: [String: Any], path: String) throws {
        let doubleValue = value.doubleValue
        if let minimum = schema[SchemaKeys.minimum] as? NSNumber {
            let minValue = minimum.doubleValue
            if doubleValue < minValue {
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Value is below minimum: \(minimum). Got: \(value)"
                )
            }
        }
        if let maximum = schema[SchemaKeys.maximum] as? NSNumber {
            let maxValue = maximum.doubleValue
            if doubleValue > maxValue {
                throw SBOMValidatorError.constraintViolation(
                    path: path,
                    message: "Value is above maximum: \(maximum). Got: \(value)"
                )
            }
        }
    }

    // MARK: - Schema Resolution and Collection Helpers
    
    /// Struct to hold all collected schema metadata in a single pass
    private struct SchemaMetadata {
        var required: [String] = []
        var properties: [String: [String: Any]] = [:]
        var allowedProperties: Set<String> = []
        var evaluatedProperties: Set<String> = []
    }
    
    /// Collect all schema metadata in a single iterative pass for better performance
    /// Uses an iterative approach with cycle detection to avoid stack overflow and improve performance
    private func collectSchemaMetadata(from schema: [String: Any]) async -> SchemaMetadata {
        var metadata = SchemaMetadata()
        var queue: [[String: Any]] = [schema]
        var visited = Set<String>() // Track by schema identity to avoid reprocessing
        
        while let current = queue.popLast() {
            // Create unique identifier for this schema to detect cycles
            let schemaId = self.createSchemaIdentifier(current)
            guard !visited.contains(schemaId) else { continue }
            visited.insert(schemaId)
            
            // 1. Collect required properties
            if let required = current[SchemaKeys.required] as? [String] {
                metadata.required.append(contentsOf: required)
                metadata.evaluatedProperties.formUnion(required)
            }
            
            // 2. Collect properties
            if let properties = current[SchemaKeys.properties] as? [String: [String: Any]] {
                metadata.properties.merge(properties) { _, new in new }
                metadata.allowedProperties.formUnion(properties.keys)
                metadata.evaluatedProperties.formUnion(properties.keys)
            }
            
            // 3. Handle $ref - resolve once and add to queue
            if let ref = current[SchemaKeys.ref] as? String, ref.hasPrefix("#/") {
                if let resolved = await self.resolveAndCacheReference(ref) {
                    queue.append(resolved)
                }
            }
            
            // 4. Handle allOf - all schemas must be satisfied
            if let allOf = current[SchemaKeys.allOf] as? [[String: Any]] {
                queue.append(contentsOf: allOf)
            }
            
            // 5. Handle anyOf/oneOf - collect allowed properties only
            for compositionKey in [SchemaKeys.anyOf, SchemaKeys.oneOf] {
                if let schemas = current[compositionKey] as? [[String: Any]] {
                    for subSchema in schemas {
                        // Extract properties without recursing
                        if let properties = subSchema[SchemaKeys.properties] as? [String: [String: Any]] {
                            metadata.allowedProperties.formUnion(properties.keys)
                            metadata.evaluatedProperties.formUnion(properties.keys)
                        }
                        
                        // Handle $ref in composition schemas
                        if let ref = subSchema[SchemaKeys.ref] as? String, ref.hasPrefix("#/") {
                            if let resolved = await self.resolveAndCacheReference(ref),
                               let properties = resolved[SchemaKeys.properties] as? [String: [String: Any]] {
                                metadata.allowedProperties.formUnion(properties.keys)
                                metadata.evaluatedProperties.formUnion(properties.keys)
                            }
                        }
                    }
                }
            }
        }
        
        return metadata
    }
    
    /// Create a unique identifier for a schema to detect cycles
    private func createSchemaIdentifier(_ schema: [String: Any]) -> String {
        // Use memory address for identity-based comparison
        return String(describing: ObjectIdentifier(schema as AnyObject))
    }
    
    /// Resolve reference with caching helper
    private func resolveAndCacheReference(_ ref: String) async -> [String: Any]? {
        let pointer = String(ref.dropFirst(2))
        let components = pointer.components(separatedBy: "/")
        return await self.resolveReference(components: components, in: self.schema)
    }
    
    /// Resolve a schema reference with caching
    private func resolveReference(components: [String], in schema: [String: Any]) async -> [String: Any]? {
        let referenceKey = components.joined(separator: "/")
        
        if let cached = await Self.referenceCache.get(referenceKey) {
            return cached
        }
        
        var current: Any = schema
        for component in components {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            guard let next = dict[component] else {
                return nil
            }
            current = next
        }
        
        guard let resolvedSchema = current as? [String: Any] else {
            return nil
        }
        
        await Self.referenceCache.set(referenceKey, schema: resolvedSchema)
        return resolvedSchema
    }

    // MARK: - Utility Functions

    private func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let lhsCanonical = try? canonicalRepresentation(of: lhs),
              let rhsCanonical = try? canonicalRepresentation(of: rhs) else {
            return false
        }
        return lhsCanonical == rhsCanonical
    }

    /// Extract a concise schema name for error reporting
    private func extractSchemaName(from schema: [String: Any], index: Int) -> String {
        // Check for $ref first
        if let ref = schema["$ref"] as? String {
            let components = ref.components(separatedBy: "/")
            if let last = components.last {
                return last
            }
        }

        // Check for const type value
        if let constValue = schema["const"] as? String {
            return constValue
        }

        // Check for type in properties
        if let properties = schema["properties"] as? [String: Any],
           let typeSchema = properties["type"] as? [String: Any],
           let oneOf = typeSchema["oneOf"] as? [[String: Any]],
           let firstConst = oneOf.first?["const"] as? String
        {
            return firstConst
        }

        return "#\(index)"
    }

    /// Helper function to describe a value for debugging purposes
    func describeValue(_ value: Any, maxLength: Int = 100) -> String {
        let description: String

        switch value {
        case let str as String:
            description = "\"\(str)\""
        case let num as NSNumber:
            if self.isBoolean(num) {
                description = "\(num.boolValue) (boolean)"
            } else if self.isFloatType(num) {
                description = "\(num.doubleValue) (number)"
            } else {
                description = "\(num.intValue) (integer)"
            }
        case let array as [Any]:
            description = "[\(array.count) items]"
        case let dict as [String: Any]:
            let keys = dict.keys.sorted().prefix(5).joined(separator: ", ")
            let more = dict.keys.count > 5 ? ", ..." : ""
            description = "{keys: \(keys)\(more)}"
        case is NSNull:
            description = "null"
        default:
            description = "\(type(of: value))"
        }

        if description.count > maxLength {
            let truncated = description.prefix(maxLength - 3)
            return "\(truncated)..."
        }
        return description
    }
}
