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

import Crypto
import Foundation

// Identities on only stored in the Keychain on macOS
#if os(macOS)
import Security
#endif

public struct KeychainIdentityAttributes: Hashable, Sendable {
    public let commonName: String?
    public let hash: String

    public init(commonName: String?, hash: String) {
        self.commonName = commonName
        self.hash = hash
    }

    public static func certificateHash(_ derBytes: [UInt8]) -> String {
        Insecure.SHA1.hash(data: derBytes).map { String(format: "%02X", $0) }.joined()
    }
}

public enum KeychainIdentitySelector: Hashable, Sendable {
    case commonName(String)
    case hash(String)
}

public enum KeychainIdentityMatch: Hashable, Sendable {
    case match(index: Int)
    case notFound
    case ambiguous([KeychainIdentityAttributes])

    public static func select(
        from attributes: [KeychainIdentityAttributes],
        matching selector: KeychainIdentitySelector
    ) -> KeychainIdentityMatch {
        let matches = attributes.enumerated().filter { Self.matches($0.element, selector) }

        guard let first = matches.first else {
            return .notFound
        }

        guard matches.count == 1 else {
            return .ambiguous(matches.map(\.element))
        }

        return .match(index: first.offset)
    }

    private static func matches(_ attributes: KeychainIdentityAttributes, _ selector: KeychainIdentitySelector) -> Bool {
        switch selector {
        case .commonName(let commonName):
            return attributes.commonName == commonName
        case .hash(let hash):
            return Self.normalized(hash) == Self.normalized(attributes.hash)
        }
    }

    private static func normalized(_ hash: String) -> String {
        hash.replacingOccurrences(of: ":", with: "").uppercased()
    }
}

#if os(macOS)
public enum KeychainIdentityError: Error, CustomStringConvertible {
    case lookupFailed(status: OSStatus)
    case certificateUnavailable(status: OSStatus)

    public var description: String {
        switch self {
        case .lookupFailed(let status):
            return "Failed to search the keychain for identities: status \(status)."
        case .certificateUnavailable(let status):
            return "Failed to read the certificate of a keychain identity: status \(status)."
        }
    }
}

public enum KeychainIdentityLookup {
    case found(identity: SecIdentity, attributes: KeychainIdentityAttributes)
    case notFound
    case ambiguous([KeychainIdentityAttributes])
}

public struct KeychainIdentityStore {
    public init() {}

    public func findIdentity(matching selector: KeychainIdentitySelector) throws -> KeychainIdentityLookup {
        let identities = try Self.identities()
        let attributes = try identities.map { try Self.attributes(of: $0) }

        switch KeychainIdentityMatch.select(from: attributes, matching: selector) {
        case .match(let index):
            return .found(identity: identities[index], attributes: attributes[index])
        case .notFound:
            return .notFound
        case .ambiguous(let matches):
            return .ambiguous(matches)
        }
    }

    private static func identities() throws -> [SecIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainIdentityError.lookupFailed(status: status)
        }

        return result as? [SecIdentity] ?? []
    }

    private static func attributes(of identity: SecIdentity) throws -> KeychainIdentityAttributes {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)

        guard status == errSecSuccess, let certificate else {
            throw KeychainIdentityError.certificateUnavailable(status: status)
        }

        return KeychainIdentityAttributes(
            commonName: Self.commonName(of: certificate),
            hash: KeychainIdentityAttributes.certificateHash([UInt8](SecCertificateCopyData(certificate) as Data))
        )
    }

    private static func commonName(of certificate: SecCertificate) -> String? {
        var commonName: CFString?

        guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess else {
            return nil
        }

        return commonName as String?
    }
}
#endif
