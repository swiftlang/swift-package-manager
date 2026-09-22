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

#if canImport(NIOSSL)
import Basics
import Foundation
import NIOSSL

#if os(macOS)
import Security
#endif

public enum RegistryClientIdentity {
    case files(certificateChain: [NIOSSLCertificate], privateKey: NIOSSLPrivateKey)
    #if os(macOS)
    case keychain(SecIdentity)
    #endif
}

public enum RegistryClientIdentityError: Error, CustomStringConvertible {
    case missingFile(String)
    case invalidCertificate(path: String, reason: String)
    case invalidPrivateKey(path: String, reason: String)
    case keychainUnavailable
    case commonNameConflict(name: String, hashes: [String])
    case identityNotInKeychain(commonName: String, hash: String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "No file was found at '\(path)'."
        case .invalidCertificate(let path, let reason):
            return "The certificate at '\(path)' could not be read: \(reason)"
        case .invalidPrivateKey(let path, let reason):
            return "The private key at '\(path)' could not be read: \(reason)"
        case .keychainUnavailable:
            return "Keychain identities are only available on macOS. Use '--cert' and '--key' instead."
        case .commonNameConflict(let name, let hashes):
            var msg = "Multiple identities have the same common name \"\(name)\":"
            var i = 0
            for hash in hashes {
                msg.append("\n\(i)) \(hash) \(name)")
                i += 1
            }
            return msg
        case .identityNotInKeychain(let commonName, let hash):
            return "No identity with a Common Name of '\(commonName)' and hash '\(hash)' was found in the keychain."
        }
    }
}

public struct RegistryClientIdentityResolver {
    // All PEM-encoded certs start with 0x30 (MII)
    // https://letsencrypt.org/docs/a-warm-welcome-to-asn1-and-der/#a-little-bonus
    private static let derSequenceTag: UInt8 = 0x30

    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public func resolve(_ identity: RegistryConfiguration.Identity) throws -> RegistryClientIdentity {
        switch identity {
        case .files(let certificatePath, let privateKeyPath):
            return .files(
                certificateChain: try self.certificateChain(at: certificatePath),
                privateKey: try self.privateKey(at: privateKeyPath)
            )
        case .keychain(let commonName, let hash):
            return try Self.keychainIdentity(commonName: commonName, hash: hash)
        }
    }

    private func certificateChain(at path: String) throws -> [NIOSSLCertificate] {
        let bytes = try self.bytes(at: path)

        do {
            guard Self.isDER(bytes) else {
                // Assume it's a PEM if it doesn't start with 0x30
                return try NIOSSLCertificate.fromPEMBytes(bytes)
            }
            return [try NIOSSLCertificate(bytes: bytes, format: .der)]
        } catch {
            throw RegistryClientIdentityError.invalidCertificate(path: path, reason: error.interpolationDescription)
        }
    }

    private func privateKey(at path: String) throws -> NIOSSLPrivateKey {
        let bytes = try self.bytes(at: path)

        do {
            return try NIOSSLPrivateKey(bytes: bytes, format: Self.isDER(bytes) ? .der : .pem)
        } catch {
            throw RegistryClientIdentityError.invalidPrivateKey(path: path, reason: error.interpolationDescription)
        }
    }

    private func bytes(at path: String) throws -> [UInt8] {
        let absolutePath = try AbsolutePath(validating: path)

        guard self.fileSystem.exists(absolutePath) else {
            throw RegistryClientIdentityError.missingFile(path)
        }

        return [UInt8](try self.fileSystem.readFileContents(absolutePath) as Data)
    }

    private static func isDER(_ bytes: [UInt8]) -> Bool {
        bytes.first == Self.derSequenceTag
    }

    private static func keychainIdentity(commonName: String, hash: String) throws -> RegistryClientIdentity {
        #if os(macOS)
        return try Self.keychainIdentity(
            from: try KeychainIdentityStore().findIdentity(matching: .hash(hash)),
            commonName: commonName,
            hash: hash
        )
        #else
        throw RegistryClientIdentityError.keychainUnavailable
        #endif
    }

    #if os(macOS)
    static func keychainIdentity(
        from lookup: KeychainIdentityLookup,
        commonName: String,
        hash: String
    ) throws -> RegistryClientIdentity {
        switch lookup {
        case .found(let identity, _):
            return .keychain(identity)
        // TODO: when does this error fire, and when does PackageRegistryCommand.ValidationError.ambiguousIdentityCommonName
        case .ambiguous(let attributes):
            throw RegistryClientIdentityError.commonNameConflict(name: commonName, hashes: attributes.map(\.hash))
        case .notFound:
            throw RegistryClientIdentityError.identityNotInKeychain(commonName: commonName, hash: hash)
        }
    }
    #endif
}
#endif
