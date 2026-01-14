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

// MARK: - Bundle.module accessor
// Provides access to the module's resource bundle across all platforms
private extension Bundle {
    static func getSBOMModule() -> Bundle? {
        // Avoid using Bundle.module directly because it results in a fatal error if not found
        let bundleName = "SwiftPM_SBOMModel"
        for bundle in Bundle.allBundles {
            if bundle.bundleURL.lastPathComponent == "\(bundleName).bundle" {
                return bundle
            }
        }
        return nil
    }
}

internal struct SBOMSchema {
    private let schema: [String: Any]

    internal init(from schemaFilename: String) throws {
        guard let bundle = Bundle.getSBOMModule() else {
            throw SBOMSchemaError.bundleNotFound(bundleName: "SwiftPM_SBOMModel")
        }
        
        guard let schemaURL = bundle.url(forResource: schemaFilename, withExtension: "json") else {
            throw SBOMSchemaError.schemaFileNotFound(
                filename: schemaFilename,
                bundlePath: bundle.bundlePath
            )
        }
        let schemaData = try Data(contentsOf: schemaURL)
        guard let jsonObject = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw SBOMSchemaError.invalidSchemaFormat(message: "Could not parse schema as JSON dictionary")
        }
        self.schema = jsonObject
    }

    internal func validate(json jsonObject: Any, spec: SBOMSpec) async throws {
        let validator = try createValidator(for: spec)
        try await validator.validate(jsonObject)
    }

    private func createValidator(for spec: SBOMSpec) throws -> any SBOMValidatorProtocol {
        switch spec.type {
        case .cyclonedx, .cyclonedx1:
            CycloneDXValidator(schema: self.schema)
        case .spdx, .spdx3:
            SPDXValidator(schema: self.schema)
            // case .cyclonedx2:
            //     return CycloneDX2Validator(schema: schema)
            // case .spdx4:
            //     return SPDX4Validator(schema: schema)
        }
    }
}
