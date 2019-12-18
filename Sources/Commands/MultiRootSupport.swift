/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import class PackageModel.Manifest
import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

/// A bare minimum loader for Xcode workspaces.
///
/// Warning: This is only useful for debugging workspaces that contain Swift packages.
public final class XcodeWorkspaceLoader {

    /// The parsed location.
    private struct Location {
        /// The kind of location.
        enum Kind: String {
            case absolute
            case group
        }

        var kind: Kind
        var path: String
    }

    let diagnostics: DiagnosticsEngine

    let fs: FileSystem

    public init(diagnostics: DiagnosticsEngine, fs: FileSystem = localFileSystem) {
        self.diagnostics = diagnostics
        self.fs = fs
    }

    /// Load the given workspace and return the file ref paths from it.
    public func load(workspace: AbsolutePath) throws -> [AbsolutePath] {
        let path = workspace.appending(component: "contents.xcworkspacedata")
        let contents = try Data(fs.readFileContents(path).contents)

        let delegate = ParserDelegate(diagnostics: diagnostics)
        let parser = XMLParser(data: contents)
        parser.delegate = delegate
        if !parser.parse() {
            throw StringError("unable to load file refs from \(path)")
        }

        /// Convert the parsed result into absolute paths.
        var result: [AbsolutePath] = []
        for location in delegate.locations {
            let path: AbsolutePath

            switch location.kind {
            case .absolute:
                path = try AbsolutePath(validating: location.path)
            case .group:
                path = AbsolutePath(location.path, relativeTo: workspace.parentDirectory)
            }

            if fs.exists(path.appending(component: Manifest.filename)) {
                result.append(path)
            } else {
                diagnostics.emit(warning: "ignoring non-package fileref \(path)")
            }
        }
        return result
    }

    /// Parser delegate for the workspace.
    private class ParserDelegate: NSObject, XMLParserDelegate {
        var locations: [Location] = []

        let diagnostics: DiagnosticsEngine

        init(diagnostics: DiagnosticsEngine) {
            self.diagnostics = diagnostics
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String : String] = [:]
        ) {
            guard elementName == "FileRef" else { return }
            guard let location = attributeDict["location"] else { return }

            let splitted = location.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard splitted.count == 2 else {
                diagnostics.emit(warning: "location split count is not two: \(splitted)")
                return
            }
            guard let kind = Location.Kind(rawValue: splitted[0]) else {
                diagnostics.emit(warning: "unknown kind \(splitted[0]) for location \(location)")
                return
            }

            locations.append(Location(kind: kind, path: splitted[1]))
        }
    }
}
