//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import Workspace
import Testing

import _InternalTestSupport

fileprivate struct ProxyStorageTests {
    @Test
    func loadValidConfig() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        try fs.createDirectory(configFile.parentDirectory)
        try fs.writeFileContents(
            configFile,
            string: """
            {
              "version": 1,
              "http": { "proxy": "http://proxy.example.com:8080" },
              "https": { "proxy": "http://proxy.example.com:8443" },
              "noProxy": ["localhost", "127.0.0.1"]
            }
            """
        )

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        let config = try storage.get()

        #expect(config != nil)
        #expect(config?.http?.proxy == "http://proxy.example.com:8080")
        #expect(config?.https?.proxy == "http://proxy.example.com:8443")
        #expect(config?.noProxy == ["localhost", "127.0.0.1"])
    }

    @Test
    func loadReturnsNilWhenFileDoesNotExist() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        let config = try storage.get()

        #expect(config == nil)
    }

    @Test
    func setHTTPProxy() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        try storage.set(httpProxy: "http://proxy:8080")

        let config = try storage.get()
        #expect(config?.http?.proxy == "http://proxy:8080")
        #expect(config?.https == nil)
    }

    @Test
    func setIsAdditive() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)

        // Set HTTP proxy
        try storage.set(httpProxy: "http://proxy:8080")

        // Add HTTPS proxy — should preserve HTTP
        try storage.set(httpsProxy: "http://proxy:8443")

        let config = try storage.get()
        #expect(config?.http?.proxy == "http://proxy:8080")
        #expect(config?.https?.proxy == "http://proxy:8443")
    }

    @Test
    func setNoProxy() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        try storage.set(httpProxy: "http://proxy:8080", noProxy: ["localhost", ".internal.corp"])

        let config = try storage.get()
        #expect(config?.noProxy == ["localhost", ".internal.corp"])
    }

    @Test
    func unsetHTTPOnly() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        try storage.set(httpProxy: "http://proxy:8080", httpsProxy: "http://proxy:8443")

        // Unset only HTTP
        try storage.unset(http: true)

        let config = try storage.get()
        #expect(config?.http == nil)
        #expect(config?.https?.proxy == "http://proxy:8443")
    }

    @Test
    func unsetAll() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)
        try storage.set(httpProxy: "http://proxy:8080")

        // Unset all (no flags = remove file)
        try storage.unset()

        #expect(!fs.exists(configFile))
        let config = try storage.get()
        #expect(config == nil)
    }

    @Test
    func deleteWhenEmpty() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs, deleteWhenEmpty: true)

        // Set then unset everything
        try storage.set(httpProxy: "http://proxy:8080")
        #expect(fs.exists(configFile))

        try storage.unset(http: true)
        // Config is now empty — file should be deleted
        #expect(!fs.exists(configFile))
    }

    @Test
    func rejectsInvalidProxyURL() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)

        #expect(throws: (any Error).self) {
            try storage.set(httpProxy: "not-a-valid-url")
        }
    }

    @Test
    func rejectsCredentialsInURL() throws {
        let fs = InMemoryFileSystem()
        let configFile = AbsolutePath("/config/proxy.json")

        let storage = Workspace.Configuration.ProxyStorage(path: configFile, fileSystem: fs)

        #expect(throws: (any Error).self) {
            try storage.set(httpProxy: "http://user:pass@proxy:8080")
        }
    }
}
