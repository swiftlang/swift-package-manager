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
import PackageGraph
import PackageModel
import TSCUtility

internal struct PURL: Codable, Equatable, CustomStringConvertible {
    internal let scheme: String
    internal let type: String
    internal let namespace: String?
    internal let name: String
    internal let version: String?
    internal let qualifiers: [String: String]?
    internal let subpath: String?

    internal init(
        scheme: String,
        type: String,
        namespace: String? = nil,
        name: String,
        version: String? = nil,
        qualifiers: [String: String]? = nil,
        subpath: String? = nil

    ) {
        self.scheme = scheme
        self.type = type
        self.namespace = namespace
        self.name = name
        self.version = version
        self.qualifiers = qualifiers
        self.subpath = subpath
    }

    internal var description: String {
        var result = "\(scheme):\(type)"
        if let namespace {
            result += "/\(namespace)"
        }
        result += "/\(self.name)"
        if let version, version != "unknown" {
            result += "@\(version)"
        }
        if let qualifiers, !qualifiers.isEmpty {
            let qualifierPairs = qualifiers.map { "\($0.key)=\($0.value)" }.sorted()
            result += "?" + qualifierPairs.joined(separator: "&")
        }
        if let subpath {
            result += "#\(subpath)"
        }
        return result
    }
}

extension PURL {
    internal static func from(package: ResolvedPackage, version: SBOMComponent.Version) async -> PURL {
        let namespace = await extractNamespace(from: version.commit)
        let qualifiers = await extractQualifiers(from: version.commit)
        return PURL(
            scheme: "pkg",
            type: "swift",
            namespace: namespace,
            name: SBOMExtractor.extractComponentID(from: package).value,
            version: version.revision,
            qualifiers: qualifiers
        )
    }

    internal static func from(product: ResolvedProduct, version: SBOMComponent.Version) async -> PURL {
        let namespace = await extractNamespace(from: version.commit)
        let qualifiers = await extractQualifiers(from: version.commit)

        return PURL(
            scheme: "pkg",
            type: "swift",
            namespace: (namespace == nil && qualifiers == nil) ? product.packageIdentity.description : namespace,
            name: SBOMExtractor.extractComponentID(from: product).value,
            version: version.revision,
            qualifiers: qualifiers
        )
    }

    internal static func extractNamespace(from commit: SBOMCommit?) async -> String? {
        guard let packageLocation = commit?.repository else {
            return nil
        }
        // local absolute file system paths: no namespace
        // path will be included in the qualifiers:
        // pkg:swift/FooPackage@1.0.0?path=/Users/jdoe/workspace/project/lib/FooPackage
        if packageLocation.hasPrefix("/") {
            return nil
        }
        // SSH URLs (git@host:org/repo.git or git@host:org/repo)
        let sshPattern = #"^[^@]+@([^:]+):([^/]+)(?:/.*)?$"#
        if let regex = try? NSRegularExpression(pattern: sshPattern, options: []),
           let match = regex.firstMatch(
               in: packageLocation,
               options: [],
               range: NSRange(location: 0, length: packageLocation.count)
           ),
           match.numberOfRanges == 3
        {
            let hostRange = Range(match.range(at: 1), in: packageLocation)
            let orgRange = Range(match.range(at: 2), in: packageLocation)
            if let hostRange, let orgRange {
                let host = String(packageLocation[hostRange])
                let org = String(packageLocation[orgRange])
                return "\(host)/\(org)"
            }
        }
        // HTTP/HTTPS URLs
        if let url = URL(string: packageLocation), let host = url.host {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if pathComponents.count >= 2 {
                let org = pathComponents[0] // swiftlang
                return "\(host)/\(org)"
            }
        }
        // com.example.package-name format
        if packageLocation.contains(".") && !packageLocation.hasPrefix("/") && !packageLocation
            .contains("://") && !packageLocation.contains("@")
        {
            let components = packageLocation.components(separatedBy: ".")
            if components.count >= 2 {
                return components.dropLast().joined(separator: ".") // com.example
            }
        }
        return nil
    }

    internal static func extractQualifiers(from commit: SBOMCommit?) async -> [String: String]? {
        guard let packageLocation = commit?.repository else {
            return nil
        }
        if packageLocation.hasPrefix("/") {
            return ["path": packageLocation]
        }
        return nil
    }
}
