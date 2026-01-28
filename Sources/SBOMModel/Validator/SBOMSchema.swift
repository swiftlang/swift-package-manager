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

private final class BundleCache {
    static let shared = BundleCache()
    
    private let lock = NSLock()
    private var cache: [String: Bundle] = [:]
    
    private init() {}
    
    func findBundle(named bundleName: String) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cachedBundle = cache[bundleName] {
            return cachedBundle
        }
        
        let foundBundle = searchForBundle(named: bundleName)
        
        if let foundBundle = foundBundle {
            cache[bundleName] = foundBundle
        }
        
        return foundBundle
    }
    
    private func searchForBundle(named bundleName: String) -> Bundle? {
        // Avoid using Bundle.module because it causes a fatal error if not found (e.g., when using custom toolchains)
        // Avoid using Bundle.allBundles because it's not thread-safe on Linux and only includes bundles that have already been loaded from disk
        
        // On macOS, these are .bundle directories; on other platforms, they're .resources directories
        let bundleExtensions = ["bundle", "resources"]
        let searchLocations = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL]

        for ext in bundleExtensions {
            for searchLocation in searchLocations {
                guard let searchURL = searchLocation?.deletingLastPathComponent() else {
                    continue
                }
                let bundleURL = searchURL.appendingPathComponent("\(bundleName).\(ext)")
                if let bundle = Bundle(url: bundleURL) {
                    return bundle
                }
            }
        }
        return nil
    }
}

// MARK: - Bundle accessor
// Provides access to the module's resource bundle across all platforms
private extension Bundle {
    static func findBundle(named bundleName: String) -> Bundle? {
        BundleCache.shared.findBundle(named: bundleName)
    }
}

internal struct SBOMSchema {
    private let schema: [String: Any]

    internal init(from schemaFilename: String, bundleName: String = "SwiftPM_SBOMModel") throws {
        if let foundBundle = Bundle.findBundle(named: bundleName),
           let schemaURL = foundBundle.url(forResource: schemaFilename, withExtension: "json") {
            let schemaData = try Data(contentsOf: schemaURL)
            guard let jsonObject = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
                throw SBOMSchemaError.invalidSchemaFormat(message: "Could not parse schema as JSON dictionary")
            }
            self.schema = jsonObject
            return
        }

        throw SBOMSchemaError.bundleNotFound(bundleName: bundleName)
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
