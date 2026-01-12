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

#if os(Windows)
// MARK: - Bundle.module workaround for Windows
// On Windows, Bundle.module is generated as internal, so we need to provide
// a public accessor to work around this limitation.
private extension Bundle {
    static var sbomModule: Bundle {
        return Bundle(for: BundleModuleMarker.self)
    }
}

// Private marker class to identify this module's bundle
private final class BundleModuleMarker {}
#else
// On other platforms, Bundle.module is public
private extension Bundle {
    static var sbomModule: Bundle {
        return Bundle.module
    }
}
#endif

internal struct SBOMSchema {
    private let schema: [String: Any]

    internal init(from schemaFilename: String) throws {
        guard let schemaURL = Bundle.sbomModule.url(forResource: schemaFilename, withExtension: "json") else {
            throw SBOMSchemaError.schemaFileNotFound(
                filename: schemaFilename,
                bundlePath: Bundle.sbomModule.bundlePath
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
