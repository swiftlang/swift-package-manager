//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import struct Foundation.URL
#if canImport(Security)
import Security
#endif

import TSCBasic

public protocol AuthorizationProvider {
    @Sendable
    func authentication(for url: URL) -> (user: String, password: String)?
}

public protocol AuthorizationWriter {
    func addOrUpdate(for url: URL, user: String, password: String, persist: Bool, callback: @escaping (Result<Void, Error>) -> Void)

    func remove(for url: URL, callback: @escaping (Result<Void, Error>) -> Void)
}

public enum AuthorizationProviderError: Error {
    case invalidURLHost
    case notFound
    case cannotEncodePassword
    case other(String)
}

public extension AuthorizationProvider {
    @Sendable
    func httpAuthorizationHeader(for url: URL) -> String? {
        guard let (user, password) = self.authentication(for: url) else {
            return nil
        }
        let authString = "\(user):\(password)"
        guard let authData = authString.data(using: .utf8) else {
            return nil
        }
        return "Basic \(authData.base64EncodedString())"
    }
}

private extension URL {
    var authenticationID: String? {
        guard let host = host?.lowercased() else {
            return nil
        }
        return host.isEmpty ? nil : host
    }
}

// MARK: - netrc

public class NetrcAuthorizationProvider: AuthorizationProvider, AuthorizationWriter {
    // marked internal for testing
    internal let path: AbsolutePath
    private let fileSystem: FileSystem

    private let cache = ThreadSafeKeyValueStore<String, (user: String, password: String)>()

    public init(path: AbsolutePath, fileSystem: FileSystem) throws {
        self.path = path
        self.fileSystem = fileSystem
        // validate file is okay at the time of initializing the provider
        _ = try Self.load(fileSystem: fileSystem, path: path)
    }

    public func addOrUpdate(for url: URL, user: String, password: String, persist: Bool = true, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let machine = url.authenticationID else {
            return callback(.failure(AuthorizationProviderError.invalidURLHost))
        }

        if !persist {
            self.cache[machine] = (user, password)
            return callback(.success(()))
        }

        // Same entry already exists, no need to add or update
        let netrc = try? Self.load(fileSystem: self.fileSystem, path: self.path)
        guard netrc?.machines.first(where: { $0.name.lowercased() == machine && $0.login == user && $0.password == password }) == nil else {
            return callback(.success(()))
        }

        do {
            // Append to end of file
            try self.fileSystem.withLock(on: self.path, type: .exclusive) {
                let contents = try? self.fileSystem.readFileContents(self.path).contents
                try self.fileSystem.writeFileContents(self.path) { stream in
                    // Write existing contents
                    if let contents, !contents.isEmpty {
                        stream.write(contents)
                        stream.write("\n")
                    }
                    stream.write("machine \(machine) login \(user) password \(password)")
                    stream.write("\n")
                }
            }

            callback(.success(()))
        } catch {
            callback(.failure(AuthorizationProviderError.other("Failed to update netrc file at \(self.path): \(error)")))
        }
    }

    public func remove(for url: URL, callback: @escaping (Result<Void, Error>) -> Void) {
        callback(.failure(AuthorizationProviderError.other("User must edit netrc file at \(self.path) manually to remove entries")))
    }

    public func authentication(for url: URL) -> (user: String, password: String)? {
        if let machine = url.authenticationID, let cached = self.cache[machine] {
            return cached
        }
        return self.machine(for: url).map { (user: $0.login, password: $0.password) }
    }

    private func machine(for url: URL) -> Basics.Netrc.Machine? {
        if let machine = url.authenticationID, let existing = self.machines.first(where: { $0.name.lowercased() == machine }) {
            return existing
        }
        if let existing = self.machines.first(where: { $0.isDefault }) {
            return existing
        }
        return .none
    }

    // marked internal for testing
    internal var machines: [Basics.Netrc.Machine] {
        // this ignores any errors reading the file
        // initial validation is done at the time of initializing the provider
        // and if the file becomes corrupt at runtime it will handle it gracefully
        let netrc = try? Self.load(fileSystem: self.fileSystem, path: self.path)
        return netrc?.machines ?? []
    }

    private static func load(fileSystem: FileSystem, path: AbsolutePath) throws -> Netrc? {
        do {
            return try NetrcParser.parse(fileSystem: fileSystem, path: path)
        } catch NetrcError.fileNotFound, NetrcError.machineNotFound {
            // These are recoverable errors.
            return .none
        }
    }
}

// MARK: - Keychain

#if canImport(Security)
public class KeychainAuthorizationProvider: AuthorizationProvider, AuthorizationWriter {
    private let observabilityScope: ObservabilityScope

    private let cache = ThreadSafeKeyValueStore<String, (user: String, password: String)>()

    public init(observabilityScope: ObservabilityScope) {
        self.observabilityScope = observabilityScope
    }

    public func addOrUpdate(for url: URL, user: String, password: String, persist: Bool = true, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let server = url.authenticationID else {
            return callback(.failure(AuthorizationProviderError.invalidURLHost))
        }

        if !persist {
            self.cache[server] = (user, password)
            return callback(.success(()))
        }

        guard let passwordData = password.data(using: .utf8) else {
            return callback(.failure(AuthorizationProviderError.cannotEncodePassword))
        }
        let `protocol` = self.protocol(for: url)

        do {
            if !(try self.update(server: server, protocol: `protocol`, account: user, password: passwordData)) {
                try self.create(server: server, protocol: `protocol`, account: user, password: passwordData)
            }
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }

    public func remove(for url: URL, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let server = url.authenticationID else {
            return callback(.failure(AuthorizationProviderError.invalidURLHost))
        }

        let `protocol` = self.protocol(for: url)

        do {
            try self.delete(server: server, protocol: `protocol`)
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }

    public func authentication(for url: URL) -> (user: String, password: String)? {
        guard let server = url.authenticationID else {
            return nil
        }

        if let cached = self.cache[server] {
            return cached
        }

        do {
            guard let existingItem = try self.search(server: server, protocol: self.protocol(for: url)) as? [String: Any],
                  let passwordData = existingItem[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: String.Encoding.utf8),
                  let account = existingItem[kSecAttrAccount as String] as? String
            else {
                throw AuthorizationProviderError.other("Failed to extract credentials for server \(server) from keychain")
            }
            return (user: account, password: password)
        } catch {
            switch error {
            case AuthorizationProviderError.notFound:
                self.observabilityScope.emit(debug: "No credentials found for server \(server) in keychain")
            case AuthorizationProviderError.other(let detail):
                self.observabilityScope.emit(error: detail)
            default:
                self.observabilityScope.emit(error: "Failed to find credentials for server \(server) in keychain: \(error)")
            }
            return nil
        }
    }

    private func create(server: String, protocol: CFString, account: String, password: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecAttrProtocol as String: `protocol`,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: password]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthorizationProviderError.other("Failed to save credentials for server \(server) to keychain: status \(status)")
        }
    }

    private func update(server: String, protocol: CFString, account: String, password: Data) throws -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecAttrProtocol as String: `protocol`]
        let attributes: [String: Any] = [kSecAttrAccount as String: account,
                                         kSecValueData as String: password]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            return false
        }
        guard status == errSecSuccess else {
            throw AuthorizationProviderError.other("Failed to update credentials for server \(server) in keychain: status \(status)")
        }
        return true
    }

    private func delete(server: String, protocol: CFString) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecAttrProtocol as String: `protocol`]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw AuthorizationProviderError.other("Failed to delete credentials for server \(server) from keychain: status \(status)")
        }
    }

    private func search(server: String, protocol: CFString) throws -> CFTypeRef? {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecAttrProtocol as String: `protocol`,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnData as String: true]

        var item: CFTypeRef?
        // Search keychain for server's username and password, if any.
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            throw AuthorizationProviderError.notFound
        }
        guard status == errSecSuccess else {
            throw AuthorizationProviderError.other("Failed to find credentials for server \(server) in keychain: status \(status)")
        }

        return item
    }

    private func `protocol`(for url: URL) -> CFString {
        // See https://developer.apple.com/documentation/security/keychain_services/keychain_items/item_attribute_keys_and_values?language=swift
        // for a list of possible values for the `kSecAttrProtocol` attribute.
        switch url.scheme?.lowercased() {
        case "https":
            return kSecAttrProtocolHTTPS
        default:
            return kSecAttrProtocolHTTPS
        }
    }
}
#endif

// MARK: - Composite

public struct CompositeAuthorizationProvider: AuthorizationProvider {
    // marked internal for testing
    internal let providers: [AuthorizationProvider]
    private let observabilityScope: ObservabilityScope

    public init(_ providers: AuthorizationProvider..., observabilityScope: ObservabilityScope) {
        self.init(providers, observabilityScope: observabilityScope)
    }

    public init(_ providers: [AuthorizationProvider], observabilityScope: ObservabilityScope) {
        self.providers = providers
        self.observabilityScope = observabilityScope
    }

    public func authentication(for url: URL) -> (user: String, password: String)? {
        for provider in self.providers {
            if let authentication = provider.authentication(for: url) {
                switch provider {
                case let provider as NetrcAuthorizationProvider:
                    self.observabilityScope.emit(info: "Credentials for \(url) found in netrc file at \(provider.path)")
                #if canImport(Security)
                case is KeychainAuthorizationProvider:
                    self.observabilityScope.emit(info: "Credentials for \(url) found in keychain")
                #endif
                default:
                    self.observabilityScope.emit(info: "Credentials for \(url) found in \(provider)")
                }
                return authentication
            }
        }
        return nil
    }
}
