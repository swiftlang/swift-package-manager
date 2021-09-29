/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import TSCUtility
import XCTest

class PackageDescriptionLoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(toolchain: ToolchainConfiguration.default)
    
    var toolsVersion: ToolsVersion {
        fatalError("implement in subclass")
    }
    
    func loadManifestThrowing(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        try self.loadManifestThrowing(ByteString(encodingAsUTF8: contents),
                                      toolsVersion: toolsVersion,
                                      packageKind: packageKind,
                                      file: file,
                                      line: line,
                                      body: body)
    }

    // TODO: deprecate in favor of String version
    func loadManifestThrowing(
        _ contents: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) throws {
        let packageKind = packageKind ?? .fileSystem(.root)
        let packagePath: AbsolutePath
        switch packageKind {
        case .root(let path):
            packagePath = path
        case .fileSystem(let path):
            packagePath = path
        case .localSourceControl(let path):
            packagePath = path
        case .remoteSourceControl, .registry:
            throw InternalError("invalid package kind \(packageKind)")
        }

        let toolsVersion = toolsVersion ?? self.toolsVersion
        let fs = InMemoryFileSystem()
        let manifestPath = packagePath.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            at: packagePath,
            packageKind: packageKind,
            toolsVersion: toolsVersion,
            fileSystem: fs)
        guard m.toolsVersion == toolsVersion else {
            return XCTFail("Invalid manifest version", file: file, line: line)
        }
        body(m)
    }
    
    func loadManifest(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        self.loadManifest(ByteString(encodingAsUTF8: contents),
                          toolsVersion: toolsVersion,
                          packageKind: packageKind,
                          line: line,
                          body: body)
    }

    // TODO: deprecate in favor of String version
    func loadManifest(
        _ contents: ByteString,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
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

    func XCTAssertManifestLoadNoThrows(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        onSuccess: ((Manifest, DiagnosticsTestResult) -> Void)? = nil
    ) {
        let observability = ObservabilitySystem.bootstrapForTesting()
        
        do {
            let manifest = try loadManifest(
                contents,
                toolsVersion: toolsVersion ?? self.toolsVersion,
                packageKind: packageKind,
                diagnostics: ObservabilitySystem.topScope.makeDiagnosticsEngine(),
                file: file,
                line: line)
            
            if let onSuccess = onSuccess {
                testDiagnostics(observability.diagnostics) { result in
                    onSuccess(manifest, result)
                }
            }
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func XCTAssertManifestLoadThrows(
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        onCatch: ((Error, DiagnosticsTestResult) -> Void)? = nil
    ) {
        let observability = ObservabilitySystem.bootstrapForTesting()
        
        do {
            let manifest = try loadManifest(
                contents,
                toolsVersion: toolsVersion ?? self.toolsVersion,
                packageKind: packageKind,
                diagnostics: ObservabilitySystem.topScope.makeDiagnosticsEngine(),
                file: file,
                line: line)
            
            XCTFail("Unexpected success: \(manifest)", file: file, line: line)
        } catch {
            if let onCatch = onCatch {
                testDiagnostics(observability.diagnostics, file: file, line: line) { result in
                    onCatch(error, result)
                }
            }
        }
    }
    
    func XCTAssertManifestLoadThrows<E: Error & Equatable>(
        _ expectedError: E,
        _ contents: String,
        toolsVersion: ToolsVersion? = nil,
        packageKind: PackageReference.Kind? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        onCatch: ((DiagnosticsTestResult) -> Void)? = nil
    ) {
        XCTAssertManifestLoadThrows(contents, toolsVersion: toolsVersion, file: file, line: line) { error, result in
            if let typedError = error as? E, typedError == expectedError {
                // Everything okay
            } else {
                XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            
            onCatch?(result)
        }
    }
    
    func loadManifest(
        _ contents: String,
        toolsVersion: ToolsVersion?,
        packageKind: PackageReference.Kind? = nil,
        diagnostics: DiagnosticsEngine?,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Manifest {
        let packageKind = packageKind ?? .fileSystem(.root)
        let packagePath: AbsolutePath
        switch packageKind {
        case .root(let path):
            packagePath = path
        case .fileSystem(let path):
            packagePath = path
        case .localSourceControl(let path):
            packagePath = path
        case .remoteSourceControl, .registry:
            throw InternalError("invalid package kind \(packageKind)")
        }

        let toolsVersion = toolsVersion ?? self.toolsVersion
        let fileSystem = InMemoryFileSystem()
        let manifestPath = packagePath.appending(component: Manifest.filename)
        try fileSystem.writeFileContents(manifestPath, bytes: ByteString(encodingAsUTF8: contents))
        let manifest = try manifestLoader.load(
            at: packagePath,
            packageKind: packageKind,
            toolsVersion: toolsVersion,
            fileSystem: fileSystem,
            diagnostics: diagnostics)
        
        if manifest.toolsVersion != toolsVersion {
            XCTFail("Invalid manifest version", file: file, line: line)
        }
        
        return manifest
    }
}
