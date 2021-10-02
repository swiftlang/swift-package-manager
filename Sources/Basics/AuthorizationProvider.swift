/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Data
import struct Foundation.URL
#if canImport(Security)
import Security
#endif

import TSCBasic
import TSCUtility

public protocol AuthorizationProvider {
    func authentication(for url: Foundation.URL) -> (user: String, password: String)?
}

public enum AuthorizationProviderError: Error {
    case invalidURLHost
    case notFound
    case cannotEncodePassword
    case other(String)
}

extension AuthorizationProvider {
    public func httpAuthorizationHeader(for url: Foundation.URL) -> String? {
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

extension Foundation.URL {
    var authenticationID: String? {
        guard let host = host?.lowercased() else {
            return nil
        }
        return host.isEmpty ? nil : host
    }
}

// MARK: - netrc

public struct NetrcAuthorizationProvider: AuthorizationProvider {
    let path: AbsolutePath
    private let fileSystem: FileSystem
    
    private var underlying: TSCUtility.Netrc?
    
    var machines: [TSCUtility.Netrc.Machine] {
        self.underlying?.machines ?? []
    }

    public init(path: AbsolutePath, fileSystem: FileSystem) throws {
        self.path = path
        self.fileSystem = fileSystem
        self.underlying = try Self.load(from: path)
    }
    
    public mutating func addOrUpdate(for url: Foundation.URL, user: String, password: String, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let machine = url.authenticationID else {
            return callback(.failure(AuthorizationProviderError.invalidURLHost))
        }
        
        // Same entry already exists, no need to add or update
        guard self.machines.first(where: { $0.name.lowercased() == machine && $0.login == user && $0.password == password }) == nil else {
            return
        }
        
        do {
            // Append to end of file
            try self.fileSystem.withLock(on: self.path, type: .exclusive) {
                let contents = try? self.fileSystem.readFileContents(self.path).contents
                try self.fileSystem.writeFileContents(self.path) { stream in
                    // File does not exist yet
                    if let contents = contents {
                        stream.write(contents)
                        stream.write("\n")
                    }
                    stream.write("machine \(machine) login \(user) password \(password)")
                    stream.write("\n")
                }
            }
            
            // At this point the netrc file should exist and non-empty
            guard let netrc = try Self.load(from: self.path) else {
                throw AuthorizationProviderError.other("Failed to update netrc file at \(self.path)")
            }
            self.underlying = netrc
            
            callback(.success(()))
        } catch {
            callback(.failure(AuthorizationProviderError.other("Failed to update netrc file at \(self.path): \(error)")))
        }
    }

    public func authentication(for url: Foundation.URL) -> (user: String, password: String)? {
        self.machine(for: url).map { (user: $0.login, password: $0.password) }
    }

    private func machine(for url: Foundation.URL) -> TSCUtility.Netrc.Machine? {
        if let machine = url.authenticationID, let existing = self.machines.first(where: { $0.name.lowercased() == machine }) {
            return existing
        }
        if let existing = self.machines.first(where: { $0.isDefault }) {
            return existing
        }
        return .none
    }

    private static func load(from path: AbsolutePath) throws -> TSCUtility.Netrc? {
        do {
            return try TSCUtility.Netrc.load(fromFileAtPath: path).get()
        } catch {
            switch error {
            case Netrc.Error.fileNotFound, Netrc.Error.machineNotFound:
                // These are recoverable errors. We will just create the file and append entry to it.
                return nil
            default:
                throw error
            }
        }
    }
}

// MARK: - Keychain

#if canImport(Security)
public struct KeychainAuthorizationProvider: AuthorizationProvider {
    public init() {}
    
    public func addOrUpdate(for url: Foundation.URL, user: String, password: String, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let server = url.authenticationID else {
            return callback(.failure(AuthorizationProviderError.invalidURLHost))
        }
        guard let passwordData = password.data(using: .utf8) else {
            return callback(.failure(AuthorizationProviderError.cannotEncodePassword))
        }
        let `protocol` = self.`protocol`(for: url)
        
        do {
            if !(try self.update(server: server, protocol: `protocol`, account: user, password: passwordData)) {
                try self.create(server: server, protocol: `protocol`, account: user, password: passwordData)
            }
            callback(.success(()))
        } catch {
            callback(.failure(error))
        }
    }
    
    public func authentication(for url: Foundation.URL) -> (user: String, password: String)? {
        guard let server = url.authenticationID else {
            return nil
        }
        
        do {
            guard let existingItem = try self.search(server: server, protocol: self.`protocol`(for: url)) as? [String : Any],
                  let passwordData = existingItem[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: String.Encoding.utf8),
                  let account = existingItem[kSecAttrAccount as String] as? String else {
                throw AuthorizationProviderError.other("Failed to extract credentials for server \(server) from keychain")
            }
            return (user: account, password: password)
        } catch {
            switch error {
            case AuthorizationProviderError.notFound:
                ObservabilitySystem.topScope.emit(info: "No credentials found for server \(server) in keychain")
            case AuthorizationProviderError.other(let detail):
                ObservabilitySystem.topScope.emit(error: detail)
            default:
                ObservabilitySystem.topScope.emit(error: "Failed to find credentials for server \(server) in keychain: \(error)")
            }
            return nil
        }
    }
    
    private func create(server: String, `protocol`: CFString, account: String, password: Data) throws {
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
    
    private func update(server: String, `protocol`: CFString, account: String, password: Data) throws -> Bool {
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
    
    private func search(server: String, `protocol`: CFString) throws -> CFTypeRef? {
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
    
    private func `protocol`(for url: Foundation.URL) -> CFString {
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
    private let providers: [AuthorizationProvider]
    
    public init(_ providers: AuthorizationProvider...) {
        self.init(providers)
    }
    
    public init(_ providers: [AuthorizationProvider]) {
        self.providers = providers
    }
    
    public func authentication(for url: Foundation.URL) -> (user: String, password: String)? {
        for provider in self.providers {
            if let authentication = provider.authentication(for: url) {
                switch provider {
                case let provider as NetrcAuthorizationProvider:
                    ObservabilitySystem.topScope.emit(info: "Credentials for \(url) found in netrc file at \(provider.path)")
                case is KeychainAuthorizationProvider:
                    ObservabilitySystem.topScope.emit(info: "Credentials for \(url) found in keychain")
                default:
                    ObservabilitySystem.topScope.emit(info: "Credentials for \(url) found in \(provider)")
                }
                return authentication
            }
        }
        return nil
    }
}
