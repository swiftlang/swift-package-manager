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

struct CycloneDXValidator: SBOMValidatorProtocol {
    private let validator: SBOMValidator

    init(schema: [String: Any]) {
        self.validator = SBOMValidator(schema: schema)
    }

    func validate(_ object: Any) async throws {
        try await self.validator.validate(object)
    }

    func validateValue(_ value: Any, path: String) async throws {
        try await self.validator.validateValue(value, path: path)
    }
}
