//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageCollections
import TSCBasic
import XCTest

class PackageIndexConfigurationTests: XCTestCase {
    func testSaveAndLoad() throws {
        let url = URL(string: "https://package-index.test")!
        let configuration = PackageIndexConfiguration(url: url)
        
        let fileSystem = InMemoryFileSystem()
        let storage = PackageIndexConfigurationStorage(path: fileSystem.swiftPMConfigurationDirectory.appending(component: "index.json"), fileSystem: fileSystem)
        try storage.save(configuration)
        
        let loadedConfiguration = try storage.load()
        XCTAssertEqual(loadedConfiguration, configuration)
    }
    
    func testLoad_fileDoesNotExist() throws {
        let fileSystem = InMemoryFileSystem()
        let storage = PackageIndexConfigurationStorage(path: fileSystem.swiftPMConfigurationDirectory.appending(component: "index.json"), fileSystem: fileSystem)
        let configuration = try storage.load()
        XCTAssertNil(configuration.url)
    }
    
    func testLoad_urlOnly() throws {
        let url = URL(string: "https://package-index.test")!
        let configJSON = """
        {
            "index": {
                "url": "\(url.absoluteString)"
            }
        }
        """
        
        let fileSystem = InMemoryFileSystem()
        let configPath = fileSystem.swiftPMConfigurationDirectory.appending(component: "index.json")
        if !fileSystem.exists(configPath.parentDirectory, followSymlink: false) {
            try fileSystem.createDirectory(configPath.parentDirectory, recursive: true)
        }
        try fileSystem.writeFileContents(configPath, string: configJSON)
        
        let storage = PackageIndexConfigurationStorage(path: configPath, fileSystem: fileSystem)
        let configuration = try storage.load()
        XCTAssertEqual(configuration.url, url)
    }
}
