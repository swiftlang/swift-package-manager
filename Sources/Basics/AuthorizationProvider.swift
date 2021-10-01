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
    mutating func addOrUpdate(for url: Foundation.URL, user: String, password: String, callback: @escaping (Result<Void, Error>) -> Void)
    
    func authentication(for url: Foundation.URL) -> (user: String, password: String)?
}

public enum AuthorizationProviderError: Error {
    case noURLHost
    case notFound
    case unexpectedPasswordData
    case unexpectedError(String)
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

// MARK: - netrc

public struct NetrcAuthorizationProvider: AuthorizationProvider {
    private let path: AbsolutePath
    private let fileSystem: FileSystem
    
    private var underlying: TSCUtility.Netrc?
    
    private var machines: [TSCUtility.Netrc.Machine] {
        self.underlying?.machines ?? []
    }

    public init(path: AbsolutePath, fileSystem: FileSystem) throws {
        self.path = path
        self.fileSystem = fileSystem
        self.underlying = try Self.loadFromDisk(path: path)
    }
    
    public mutating func addOrUpdate(for url: Foundation.URL, user: String, password: String, callback: @escaping (Result<Void, Error>) -> Void) {
        guard let machineName = self.machineName(for: url) else {
            return callback(.failure(AuthorizationProviderError.noURLHost))
        }
        let machine = TSCUtility.Netrc.Machine(name: machineName, login: user, password: password)
        
        var machines = [TSCUtility.Netrc.Machine]()
        var hasExisting = false
        
        self.machines.forEach {
            if $0.name.lowercased() != machineName {
                machines.append($0)
            } else if !hasExisting {
                // Update existing entry and retain one copy only
                machines.append(machine)
                hasExisting = true
            }
        }
        
        // New entry
        if !hasExisting {
            machines.append(machine)
        }
        
        do {
            try self.saveToDisk(machines: machines)
            // At this point the netrc file should exist and non-empty
            guard let netrc = try Self.loadFromDisk(path: self.path) else {
                throw AuthorizationProviderError.unexpectedError("Failed to update netrc file at \(self.path)")
            }
            self.underlying = netrc
            callback(.success(()))
        } catch {
            callback(.failure(AuthorizationProviderError.unexpectedError("Failed to update netrc file at \(self.path): \(error)")))
        }
    }

    public func authentication(for url: Foundation.URL) -> (user: String, password: String)? {
        self.machine(for: url).map { (user: $0.login, password: $0.password) }
    }
    
    private func machineName(for url: Foundation.URL) -> String? {
        url.host?.lowercased()
    }

    private func machine(for url: Foundation.URL) -> TSCUtility.Netrc.Machine? {
        if let machineName = self.machineName(for: url), let machine = self.machines.first(where: { $0.name.lowercased() == machineName }) {
            return machine
        }
        if let machine = self.machines.first(where: { $0.isDefault }) {
            return machine
        }
        return .none
    }
    
    private func saveToDisk(machines: [TSCUtility.Netrc.Machine]) throws {
        try self.fileSystem.withLock(on: self.path, type: .exclusive) {
            try self.fileSystem.writeFileContents(self.path) { stream in
                machines.forEach {
                    stream.write("machine \($0.name) login \($0.login) password \($0.password)\n")
                }
            }
        }
    }
    
    private static func loadFromDisk(path: AbsolutePath) throws -> TSCUtility.Netrc? {
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
        guard let server = self.server(for: url) else {
            return callback(.failure(AuthorizationProviderError.noURLHost))
        }
        guard let passwordData = password.data(using: .utf8) else {
            return callback(.failure(AuthorizationProviderError.unexpectedPasswordData))
        }
        let `protocol` = self.`protocol`(for: url)
        
        do {
            try self.update(server: server, protocol: `protocol`, account: user, password: passwordData)
            callback(.success(()))
        } catch AuthorizationProviderError.notFound {
            do {
                try self.create(server: server, protocol: `protocol`, account: user, password: passwordData)
                callback(.success(()))
            } catch {
                callback(.failure(error))
            }
        } catch {
            callback(.failure(error))
        }
    }
    
    public func authentication(for url: Foundation.URL) -> (user: String, password: String)? {
        guard let server = self.server(for: url) else {
            return nil
        }
        
        do {
            guard let existingItem = try self.search(server: server, protocol: self.`protocol`(for: url)) as? [String : Any],
                  let passwordData = existingItem[kSecValueData as String] as? Data,
                  let password = String(data: passwordData, encoding: String.Encoding.utf8),
                  let account = existingItem[kSecAttrAccount as String] as? String else {
                throw AuthorizationProviderError.unexpectedError("Failed to extract credentials for server \(server) from keychain")
            }
            return (user: account, password: password)
        } catch {
            switch error {
            case AuthorizationProviderError.notFound:
                ObservabilitySystem.topScope.emit(info: "No credentials found for server \(server) in keychain")
            case AuthorizationProviderError.unexpectedError(let detail):
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
            throw AuthorizationProviderError.unexpectedError("Failed to save credentials for server \(server) to keychain: status \(status)")
        }
    }
    
    private func update(server: String, `protocol`: CFString, account: String, password: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecAttrProtocol as String: `protocol`]
        let attributes: [String: Any] = [kSecAttrAccount as String: account,
                                         kSecValueData as String: password]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            throw AuthorizationProviderError.notFound
        }
        guard status == errSecSuccess else {
            throw AuthorizationProviderError.unexpectedError("Failed to update credentials for server \(server) in keychain: status \(status)")
        }
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
            throw AuthorizationProviderError.unexpectedError("Failed to find credentials for server \(server) in keychain: status \(status)")
        }
        
        return item
    }
    
    private func server(for url: Foundation.URL) -> String? {
        url.host?.lowercased()
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
