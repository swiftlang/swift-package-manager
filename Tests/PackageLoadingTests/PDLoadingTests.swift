/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import PackageModel
import PackageLoading

class PackageDescriptionLoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(manifestResources: Resources.default)

    var toolsVersion: ToolsVersion {
        fatalError("implement in subclass")
    }

    func loadManifestThrowing(
        _ contents: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind = .local,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        let toolsVersion = toolsVersion ?? self.toolsVersion
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: "/foo",
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            fileSystem: fs)
        guard m.toolsVersion == toolsVersion else {
            return XCTFail("Invalid manfiest version")
        }
        body(m)
    }

    func loadManifest(
        _ contents: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind = .local,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        do {
            let toolsVersion = toolsVersion ?? self.toolsVersion
            try loadManifestThrowing(
                contents,
                toolsVersion: toolsVersion,
                packageKind: packageKind,
                line: line,
                body: body
            )
        } catch ManifestParseError.invalidManifestFormat(let error, _) {
            print(error)
            XCTFail(file: #file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }
}
